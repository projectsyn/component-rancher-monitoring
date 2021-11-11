local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local namespace = params.namespace;

local instance = params.prometheusInstance;
local name = 'prometheus-' + instance;
local configureThanos = std.objectHas(params.thanos, 'type');

local labels = {
  'app.kubernetes.io/name': 'prometheus',
  'app.kubernetes.io/instance': instance,
  'app.kubernetes.io/managed-by': 'syn',
};

local matchLabels = {
  prometheus: instance,
  role: 'alert-rules',
};

local defaultNsSelector = {
  matchLabels: {
    SYNMonitoring: 'main',
  },
};

local nsSelector =
  if std.objectHas(params, 'prometheusNamespaceSelector') &&
     params.prometheusNamespaceSelector != null
  then
    params.prometheusNamespaceSelector
  else
    defaultNsSelector;


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
      tenant_id: inv.parameters.cluster.tenant,
      cluster_id: inv.parameters.cluster.name,
    },
    alerting+: {
      alertmanagers+: [
        {
          name: 'alertmanager-' + params.alertmanagerInstance,
          namespace: namespace,
          port: 'web',
        },
      ],
    },
    image: params.images.prometheus.image + ':' + params.images.prometheus.tag,
    version: std.split(params.images.prometheus.tag, '@')[0],
    nodeSelector+: {
      'kubernetes.io/os': 'linux',
    },
    podMonitorNamespaceSelector+: nsSelector,
    podMonitorSelector+: {},
    ruleNamespaceSelector+: nsSelector,
    serviceMonitorNamespaceSelector+: nsSelector,
    serviceMonitorSelector+: {},
    ruleSelector+: {
      matchLabels: matchLabels,
    },
    securityContext+: {
      fsGroup: 2000,
      runAsNonRoot: true,
      runAsUser: 1000,
    },
    serviceAccountName: name,
    additionalScrapeConfigs: {
      name: 'additional-scrape-configs',
      key: 'prometheus-additional.yaml',
    },
  } + (if configureThanos then {
         thanos+: {
           image: params.images.thanos.image + ':' + params.images.thanos.tag,
           version: std.split(params.images.thanos.tag, '@')[0],
           objectStorageConfig+: {
             name: name + '-thanos',
             key: 'thanos.yaml',
           },
         },
       }
       else {}) + com.makeMergeable(params.prometheus),
};

local thanos_endpoint = if configureThanos then [
  {
    interval: '30s',
    port: 'http',
  },
] else [];

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
    ] + thanos_endpoint,
    selector: {
      matchLabels: labels,
    },
  },
};

local thanos_ports = if configureThanos then [
  {
    name: 'thanos-grpc',
    port: 10901,
    targetPort: 'grpc',
  },
  {
    name: 'thanos-http',
    port: 10902,
    targetPort: 'http',
  },
] else [];

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
    ] + thanos_ports,
    selector: {
      app: 'prometheus',
      prometheus: name,
    },
    sessionAffinity: 'ClientIP',
    type: params.prometheusServiceType,
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

local thanos_objstore = if configureThanos then kube.Secret(name + '-thanos') {
  metadata+: {
    namespace: params.namespace,
    labels+: labels,
  },
  stringData: {
    'thanos.yaml': std.manifestYamlDoc(params.thanos),
  },
}
;

std.filter(function(it) it != null, [
  serviceaccount,
  clusterrole,
  clusterrolebinding,
  prometheus,
  servicemonitor,
  service,
  thanos_objstore,
])
