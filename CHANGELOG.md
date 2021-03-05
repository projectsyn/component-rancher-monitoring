# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial open-source implementation ([#1])
- Annotate all alerts with the Syn component name ([#8])
- Allow configuring custom annotations via inventory ([#8])

### Changed

- Upgrade kube-prometheus ([#6])
- Upgrade Prometheus to v2.25.0 ([#11])
- Federation: Exclude ingress-nginx metrics ([#12])

### Fixed

- Update kube-prometheus version locks to include recent dependency fixes ([#4]).
- Update kube-prometheus repository location ([#7])
- Skip recording rules when adding custom annotations ([#10])
- Prometheus: replace deprecated attributes ([#11])

[unreleased]: https://github.com/projectsyn/component-rancher-monitoring/compare/084a263baf909b627d2861790806ac8f7de3f580...HEAD
[#1]: https://github.com/projectsyn/component-rancher-monitoring/pull/1
[#4]: https://github.com/projectsyn/component-rancher-monitoring/pull/4
[#6]: https://github.com/projectsyn/component-rancher-monitoring/pull/6
[#7]: https://github.com/projectsyn/component-rancher-monitoring/pull/7
[#8]: https://github.com/projectsyn/component-rancher-monitoring/pull/8
[#10]: https://github.com/projectsyn/component-rancher-monitoring/pull/10
[#11]: https://github.com/projectsyn/component-rancher-monitoring/pull/11
[#12]: https://github.com/projectsyn/component-rancher-monitoring/pull/12
