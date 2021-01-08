local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local namespace = params.namespace;

local instance = params.prometheusInstance;
local name = 'prometheus-' + instance;

local labels = {
  'app.kubernetes.io/name': 'prometheus',
  'app.kubernetes.io/instance': instance,
  'app.kubernetes.io/managed-by': 'syn',
};

local matchLabels = {
  prometheus: instance,
  role: 'alert-rules',
};

local nsSelector = {
  matchLabels: {
    SYNMonitoring: 'main',
  },
};

// The actual prometheus resource for the prometheus operator
local prometheus = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'Prometheus',
  metadata: {
    name: name,
    namespace: namespace,
    labels: labels,
  },
  spec: {
    externalLabels: {
      customer: inv.parameters.customer.name,
      cluster: inv.parameters.cluster.name,
    },
    alerting+: {
      alertmanagers+: [
        {
          name: "alertmanager-" + params.alertmanagerInstance,
          namespace: namespace,
          port: 'web',
        },
      ],
    },
    baseImage: params.images.prometheus.image,
    tag: params.images.prometheus.tag,
    nodeSelector+: {
      'kubernetes.io/os': 'linux',
    },
    podMonitorNamespaceSelector+: nsSelector,
    ruleNamespaceSelector+: nsSelector,
    serviceMonitorNamespaceSelector+: nsSelector,
    ruleSelector+: {
      matchLabels: matchLabels,
    },
    replicas: 1,
    resources+: {
      requests+: {
        memory: "2Gi",
        cpu: "1000m",
      },
      limits+: {
        memory: "6Gi",
        cpu: "2000m",
      },
    },
    storage+: {
      volumeClaimTemplate+: {
        spec+: {
          accessModes+: [
            'ReadWriteOnce',
          ],
          resources+: {
            requests+: {
              storage+: "10Gi"
            },
          },
        },
      },
    },
    retention: "24h",
    securityContext+: {
      fsGroup: 2000,
      runAsNonRoot: true,
      runAsUser: 1000,
    },
    serviceAccountName: name,
  } + com.makeMergeable(params.prometheus),
};

local servicemonitor = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: {
    name: name,
    namespace: namespace,
    labels: matchLabels,
  },
  spec: {
    endpoints: [
      {
        interval: '30s',
        port: 'web',
      },
    ],
    selector: {
      matchLabels: labels,
    },
  },
};

local service = kube.Service(name) {
  metadata+: {
    namespace: namespace,
    labels+: labels,
  },
  spec+: {
    ports: [
      {
        name: 'web',
        port: 9090,
        targetPort: 'web',
      },
    ],
    selector: {
      app: 'prometheus',
      prometheus: name,
    },
    sessionAffinity: 'ClientIP',
  },
};

local serviceaccount = kube.ServiceAccount(name) {
  metadata+: {
    namespace: namespace,
    labels+: labels,
  },
};

local clusterrole = kube.ClusterRole(name) {
  metadata+: {
    labels+: labels,
  },
  rules+: [
    {
      apiGroups: [
        '',
      ],
      resources: [
        'nodes',
        'services',
        'endpoints',
        'pods',
      ],
      verbs: [
        'get',
        'list',
        'watch',
      ],
    },
    {
      apiGroups: [
        '',
      ],
      resources: [
        'configmaps',
      ],
      verbs: [
        'get',
      ],
    },
    {
      nonResourceURLs: [
        '/metrics',
      ],
      verbs: [
        'get',
      ],
    },
  ],
};

local clusterrolebinding = kube.ClusterRoleBinding(name) {
  metadata+: {
    labels+: labels,
  },
  roleRef+: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: clusterrole.kind,
    name: clusterrole.metadata.name,
  },
  subjects+: [
    {
      kind: serviceaccount.kind,
      name: serviceaccount.metadata.name,
      namespace: serviceaccount.metadata.namespace,
    },
  ],
};


[
  serviceaccount,
  clusterrole,
  clusterrolebinding,
  prometheus,
  servicemonitor,
  service,
]
