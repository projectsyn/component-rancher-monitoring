local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local namespace = params.namespace;
local instance = params.alertmanagerInstance;
local name = 'alertmanager-' + instance;

local labels = {
  'app.kubernetes.io/name': 'alertmanager',
  'app.kubernetes.io/instance': instance,
  'app.kubernetes.io/managed-by': 'syn',
};

local matchLabels = {
  app: 'alertmanager',
  alertmanager: instance,
};

local sa = kube.ServiceAccount(name) {
  metadata+: {
    namespace: namespace,
    labels+: labels,
  },
};

local alertmanager = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'Alertmanager',
  metadata: {
    name: instance,
    namespace: namespace,
    labels: labels,
  },
  spec+: {
    baseImage: params.images.alertmanager.image,
    tag: params.images.alertmanager.tag,
    logLevel: 'info',
    nodeSelector+: {
      'kubernetes.io/os': 'linux',
    },
    replicas: 1,
    securityContext+: {
      fsGroup: 2000,
      runAsNonRoot: true,
      runAsUser: 1000,
    },
    serviceAccountName: sa.metadata.name,
  } + com.makeMergeable(params.alertmanager),
};

local service = kube.Service(name) {
  metadata+: {
    namespace: params.namespace,
    labels+: labels,
  },
  spec+: {
    ports: [
      {
        name: 'web',
        port: 9093,
        targetPort: 'web',
      },
    ],
    selector: matchLabels,
    sessionAffinity: 'ClientIP',
  },
};

local servicemonitor = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: {
    name: name,
    namespace: namespace,
    labels: labels,
  },
  spec: {
    endpoints: [
      {
        interval: '30s',
        port: 'web',
      },
    ],
    selector: {
      matchLabels: matchLabels,
    },
  },
};

local secret = kube.Secret(name) {
  metadata+: {
    namespace: namespace,
    labels+: labels,
  },
  stringData: {
    // TODO: consider sanitizing or verifying input config
    'alertmanager.yaml': std.manifestYamlDoc(params.alertmanagerConfig),
  },
};

[ alertmanager, sa, service, servicemonitor, secret ]
