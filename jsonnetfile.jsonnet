{
  version: 1,
  dependencies: [
    {
      source: {
        git: {
          remote: 'https://github.com/coreos/kube-prometheus',
          subdir: 'jsonnet/kube-prometheus',
        },
      },
      version: std.extVar('kube_prometheus_version'),
    },
  ],
  legacyImports: true,
}
