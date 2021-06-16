package main

import (
	"fmt"
	"io/ioutil"
	"strings"
	"testing"

	"github.com/instrumenta/kubeval/kubeval"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/yaml"
)

var (
	testPath = "../../compiled/rancher-monitoring/rancher-monitoring"
)

func validate(t *testing.T, path string) {
	files, err := ioutil.ReadDir(path)
	require.NoError(t, err)
	for _, file := range files {
		filePath := fmt.Sprintf("%s/%s", path, file.Name())
		if file.IsDir() {
			validate(t, filePath)
		} else {
			data, err := ioutil.ReadFile(filePath)
			require.NoError(t, err)

			conf := kubeval.NewDefaultConfig()
			res, err := kubeval.Validate(data, conf)
			if err != nil && strings.Contains(err.Error(), "404 Not Found") {
				// We do not have the api specification for the respecive resource we
				// skip for now
				// TODO(glrf) maybe we could load the CRD specification
				continue
			}
			require.NoError(t, err)
			for _, r := range res {
				if len(r.Errors) > 0 {
					t.Errorf("%s", filePath)
				}
				for _, e := range r.Errors {
					t.Errorf("\t %s", e)
				}
			}
		}
	}
}
func Test_Validate(t *testing.T) {
	validate(t, testPath)
}

func Test_Namespace(t *testing.T) {
	ns := corev1.Namespace{}
	data, err := ioutil.ReadFile(testPath + "/00_namespace.yaml")
	require.NoError(t, err)
	err = yaml.Unmarshal(data, &ns)
	require.NoError(t, err)
	assert.Equal(t, "syn-rancher-monitoring", ns.Name)
}
