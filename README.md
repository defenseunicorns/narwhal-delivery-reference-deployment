# narwhal-delivery-reference-deployment

This repo contains reference deployments that are intended to be able to be copy/pasted for mostly prod-ready Day Zero deployments. We intend for the deployments to be as close to production ready as possible, given the constraints of the reference deployment.

## Purpose of this repo

1. Help establish a common pattern for how we consume and extend DUBBD.
2. Give a good starting point for delivery engineers to start from when deploying a mission app.
3. Help stakeholders understand what tools/technologies/patterns are being used by our team. If we don't talk about something, it's probably not being used.

## Roadmap

1. [IN PROGRESS] "On-Prem Lite" -- Reference deployment for deploying a mission app integrated with Keycloak and DUBBD to a single-node K3s cluster.
2. [TODO] "EKS" -- Reference deployment for deploying a mission app integrated with Keycloak and DUBBD to a production-level multi-node EKS cluster. Once this is done we intend to archive the [defenseunicorns/delivery-aws-iac](https://github.com/defenseunicorns/delivery-aws-iac) repo as this will be treated as the next evolution of it.
3. [TODO] "On-Prem Full" -- Reference deployment for deploying a mission app integrated with Keycloak and DUBBD to a RKE2 cluster.
