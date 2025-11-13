package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/http"

	admv1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/ziwon/gpu-scheduler/internal/util"
)

var (
	tlsCert = flag.String("tls-cert-file", "/certs/tls.crt", "Path to TLS certificate")
	tlsKey  = flag.String("tls-private-key-file", "/certs/tls.key", "Path to TLS private key")
	addr    = flag.String("addr", ":8443", "Webhook listen address")
)

func main() {
	flag.Parse()
	http.HandleFunc("/mutate", mutate)
	if err := http.ListenAndServeTLS(*addr, *tlsCert, *tlsKey, nil); err != nil {
		panic(err)
	}
}

func mutate(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()
	var review admv1.AdmissionReview
	if err := json.NewDecoder(r.Body).Decode(&review); err != nil {
		writeResponse(w, admissionError(review, err))
		return
	}
	if review.Request == nil {
		writeResponse(w, admissionError(review, fmt.Errorf("empty request")))
		return
	}

	pod := &corev1.Pod{}
	if err := json.Unmarshal(review.Request.Object.Raw, pod); err != nil {
		writeResponse(w, admissionError(review, err))
		return
	}

	if pod.Annotations == nil || pod.Annotations[util.AnnoClaim] == "" {
		review.Response = &admv1.AdmissionResponse{
			UID:     review.Request.UID,
			Allowed: true,
		}
		writeResponse(w, review)
		return
	}
	response := &admv1.AdmissionResponse{
		UID:     review.Request.UID,
		Allowed: true,
	}
	if len(pod.Spec.Containers) == 0 {
		review.Response = response
		writeResponse(w, review)
		return
	}

	patch := buildPatch(pod)
	patchBytes, err := json.Marshal(patch)
	if err != nil {
		writeResponse(w, admissionError(review, err))
		return
	}

	pt := admv1.PatchTypeJSONPatch
	response.PatchType = &pt
	response.Patch = patchBytes
	review.Response = response
	writeResponse(w, review)
}

const annotationFieldPath = "metadata.annotations['" + util.AnnoAllocated + "']"

func buildPatch(pod *corev1.Pod) []map[string]interface{} {
	var ops []map[string]interface{}
	for i, c := range pod.Spec.Containers {
		envPath := fmt.Sprintf("/spec/containers/%d/env", i)
		value := map[string]interface{}{
			"name": "CUDA_VISIBLE_DEVICES",
			"valueFrom": map[string]interface{}{
				"fieldRef": map[string]string{
					"fieldPath": annotationFieldPath,
				},
			},
		}
		switch idx := envIndex(c.Env, value["name"].(string)); {
		case idx == -1 && len(c.Env) == 0:
			ops = append(ops, map[string]interface{}{
				"op":    "add",
				"path":  envPath,
				"value": []map[string]interface{}{value},
			})
		case idx == -1:
			ops = append(ops, map[string]interface{}{
				"op":    "add",
				"path":  envPath + "/-",
				"value": value,
			})
		default:
			ops = append(ops, map[string]interface{}{
				"op":    "replace",
				"path":  fmt.Sprintf("%s/%d", envPath, idx),
				"value": value,
			})
		}
	}
	return ops
}

func envIndex(vars []corev1.EnvVar, name string) int {
	for i, env := range vars {
		if env.Name == name {
			return i
		}
	}
	return -1
}

func admissionError(review admv1.AdmissionReview, err error) admv1.AdmissionReview {
	review.Response = &admv1.AdmissionResponse{
		Result: &metav1.Status{
			Message: err.Error(),
		},
	}
	return review
}

func writeResponse(w http.ResponseWriter, review admv1.AdmissionReview) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(review)
}
