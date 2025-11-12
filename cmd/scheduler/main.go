package main

import (
	"os"

	"k8s.io/component-base/cli"
	_ "k8s.io/component-base/logs/json/register"
	"k8s.io/kubernetes/cmd/kube-scheduler/app"

	"github.com/aaronlab/gpu-scheduler/internal/plugin/gpuclaim"
)

func main() {
	command := app.NewSchedulerCommand(
		app.WithPlugin(gpuclaim.Name, gpuclaim.New),
	)

	code := cli.Run(command)
	os.Exit(code)
}
