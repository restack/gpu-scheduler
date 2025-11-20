package lease

import (
	"context"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clientset "k8s.io/client-go/kubernetes"
	"k8s.io/klog/v2"
)

const (
	gcInterval   = 30 * time.Second
	labelManaged = "gpu.scheduling/managed"
	labelPod     = "gpu.scheduling/pod"
)

// StartGC runs a background loop to clean up orphaned leases.
func StartGC(ctx context.Context, client clientset.Interface) {
	go func() {
		ticker := time.NewTicker(gcInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				runGC(ctx, client)
			}
		}
	}()
}

func runGC(ctx context.Context, client clientset.Interface) {
	// List all leases managed by us
	leases, err := client.CoordinationV1().Leases("").List(ctx, metav1.ListOptions{
		LabelSelector: labelManaged + "=true",
	})
	if err != nil {
		klog.ErrorS(err, "GC: failed to list leases")
		return
	}

	for _, lease := range leases.Items {
		podName := lease.Labels[labelPod]
		if podName == "" {
			continue
		}

		// Check if pod exists and is active
		pod, err := client.CoreV1().Pods(lease.Namespace).Get(ctx, podName, metav1.GetOptions{})
		if err != nil {
			if errors.IsNotFound(err) {
				// Pod is gone, delete lease
				klog.InfoS("GC: deleting lease for missing pod", "lease", lease.Name, "pod", podName)
				deleteLease(ctx, client, lease.Namespace, lease.Name)
			} else {
				klog.ErrorS(err, "GC: failed to get pod", "pod", podName)
			}
			continue
		}

		// Check if pod is completed or failed
		if pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			klog.InfoS("GC: deleting lease for completed/failed pod", "lease", lease.Name, "pod", podName, "phase", pod.Status.Phase)
			deleteLease(ctx, client, lease.Namespace, lease.Name)
			continue
		}

		// Check if pod UID matches holder identity
		if lease.Spec.HolderIdentity != nil && string(pod.UID) != *lease.Spec.HolderIdentity {
			klog.InfoS("GC: deleting lease for UID mismatch", "lease", lease.Name, "pod", podName, "podUID", pod.UID, "holder", *lease.Spec.HolderIdentity)
			deleteLease(ctx, client, lease.Namespace, lease.Name)
		}
	}
}

func deleteLease(ctx context.Context, client clientset.Interface, ns, name string) {
	if err := client.CoordinationV1().Leases(ns).Delete(ctx, name, metav1.DeleteOptions{}); err != nil {
		if !errors.IsNotFound(err) {
			klog.ErrorS(err, "GC: failed to delete lease", "lease", name)
		}
	}
}
