package lease

import (
	"context"
	"testing"

	coordv1 "k8s.io/api/coordination/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/fake"
)

func TestRunGC(t *testing.T) {
	ctx := context.Background()
	client := fake.NewSimpleClientset()

	// 1. Create a lease for a missing pod
	leaseMissingPod := &coordv1.Lease{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "lease-missing-pod",
			Namespace: "default",
			Labels: map[string]string{
				labelManaged: "true",
				labelPod:     "missing-pod",
			},
		},
	}
	_, _ = client.CoordinationV1().Leases("default").Create(ctx, leaseMissingPod, metav1.CreateOptions{})

	// 2. Create a lease for a running pod (should keep)
	podRunning := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "running-pod",
			Namespace: "default",
			UID:       "uid-running",
		},
		Status: corev1.PodStatus{Phase: corev1.PodRunning},
	}
	_, _ = client.CoreV1().Pods("default").Create(ctx, podRunning, metav1.CreateOptions{})

	holderRunning := "uid-running"
	leaseRunningPod := &coordv1.Lease{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "lease-running-pod",
			Namespace: "default",
			Labels: map[string]string{
				labelManaged: "true",
				labelPod:     "running-pod",
			},
		},
		Spec: coordv1.LeaseSpec{
			HolderIdentity: &holderRunning,
		},
	}
	_, _ = client.CoordinationV1().Leases("default").Create(ctx, leaseRunningPod, metav1.CreateOptions{})

	// 3. Create a lease for a completed pod (should delete)
	podCompleted := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "completed-pod",
			Namespace: "default",
			UID:       "uid-completed",
		},
		Status: corev1.PodStatus{Phase: corev1.PodSucceeded},
	}
	_, _ = client.CoreV1().Pods("default").Create(ctx, podCompleted, metav1.CreateOptions{})

	holderCompleted := "uid-completed"
	leaseCompletedPod := &coordv1.Lease{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "lease-completed-pod",
			Namespace: "default",
			Labels: map[string]string{
				labelManaged: "true",
				labelPod:     "completed-pod",
			},
		},
		Spec: coordv1.LeaseSpec{
			HolderIdentity: &holderCompleted,
		},
	}
	_, _ = client.CoordinationV1().Leases("default").Create(ctx, leaseCompletedPod, metav1.CreateOptions{})

	// Run GC
	runGC(ctx, client)

	// Verify results
	leases, _ := client.CoordinationV1().Leases("default").List(ctx, metav1.ListOptions{})
	if len(leases.Items) != 1 {
		t.Errorf("Expected 1 lease, got %d", len(leases.Items))
	}

	if leases.Items[0].Name != "lease-running-pod" {
		t.Errorf("Expected lease-running-pod to remain, got %s", leases.Items[0].Name)
	}
}
