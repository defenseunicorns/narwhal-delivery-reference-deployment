# narwhal-delivery-reference-deployment

This repo contains the reference deployment that is intended to be able to be copy/pasted for a mostly prod-ready Day Zero deployment. We intend for the deployment to be as close to production ready as possible, given the constraints of the reference deployment.

## Purpose of this repo

1. Help establish a common pattern for how we consume and extend DUBBD.
2. Give a good starting point for delivery engineers to start from when deploying a mission app.
3. Help stakeholders understand what tools/technologies/patterns are being used by our team. If we don't talk about something, it's probably not being used.

## Components of this deployment

The following is a list of everything that goes into this deployment. Each item is separately deployed in the order listed.

1. Zarf Init Package
2. Zarf Package for MetalLB
3. Zarf Package for DUBBD
4. Zarf Package for IDAM (Keycloak)
5. Zarf Package for SSO (AuthService)
6. Zarf Package for the mission app. In this case, the simple Podinfo app is being used as a standin for the mission app.

## Maturity Level and Suitability for Day-2 Operations

This reference deployment uses several components that are still in the early stages of development. As such, this reference deployment should be considered to be at the "Experimental" maturity level.

| Component                                                         | Maturity Level   | Notes                                                                                                                                 |
|-------------------------------------------------------------------|------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| [Zarf](https://github.com/defenseunicorns/zarf)                   | Late-Stage Beta  | We are comfortable using Zarf in production, despite its v0.X status.                                                                 |
| [MetalLB](https://github.com/defenseunicorns/uds-package-metallb) | Experimental     | The Zarf Package for MetalLB is very new and does not yet meet our qualifications for being used in production.                       |
| [DUBBD](https://github.com/defenseunicorns/uds-package-dubbd)     | Mid-Stage Beta   | We intend to use DUBBD in production at some point, but are anticipating a lot of churn which will likely cause some pain.            |
| [IDAM](https://github.com/defenseunicorns/uds-idam)               | Early-Stage Beta | We intend to use the IDAM package in production at some point, but are anticipating a lot of churn which will likely cause some pain. |
| [SSO](https://github.com/defenseunicorns/uds-sso)                 | Early-Stage Beta | We intend to use the SSO package in production at some point, but are anticipating a lot of churn which will likely cause some pain.  |

## Prerequisites

> NOTE: The prerequisites assume you already have a Kubernetes cluster. If you don't have one and want to create a K3s cluster using Zarf, run `sudo zarf init --components=k3s,git-server --set K3S_ARGS="--disable traefik,servicelb" --confirm`. If this is the way you go, all subsequent commands will need to be run with `sudo` as well.

- A Kubernetes cluster with the following criteria:
  - uses amd64 architecture (sorry ARM, the Big Bang people still haven't gotten around to you yet).
  - No existing ingress controllers or ServiceLB. If you are using K3s Traefik and ServiceLB have to be **disabled**.
  - The version of K8s is a modern and supported one that is not EOL (End Of Life).
  - The cluster has enough CPU and RAM available (exact numbers TBD)
  - Zarf has already been initialized on the cluster with the optional `git-server` component enabled.

> If you don't have a cluster yet, create one on the local (Linux) machine with `sudo zarf init --components=k3s,git-server --set K3S_ARGS="--disable traefik,servicelb" --confirm`. If this is the way you go, all subsequent commands will need to be run with `sudo` as well.
>
> If you do already have a cluster, initialize Zarf with `sudo zarf init --components=git-server --set K3S_ARGS="--disable traefik,servicelb" --confirm`

- Local access to the K8s cluster. `kubectl get nodes` should work and return the nodes in the cluster.
- The following tools installed locally and available on the $PATH:
  - [make](https://www.gnu.org/software/make/)
  - [zarf](https://github.com/defenseunicorns/zarf)
- A file called `zarf-config.yaml` in this directory that has YOUR values configured in it. See `zarf-config.example.yaml` for an example.
- A file called `tls.cert` in this directory that has your TLS cert in it. See `zarf-config.example.yaml` for more details.
- A file called `tls.key` in this directory that has your TLS key in it. See `zarf-config.example.yaml` for more details.

  > NOTE: The `zarf-config.yaml`, `tls.cert`, and `tls.key` files should be treated as secrets, since they will have sensitive environment-specific data in them. They should not be checked into source control.

## Objective

To have the mission app deployed and integrated with DUBBD and Keycloak in the single-node K3s cluster on the server, and to be properly redirected to Keycloak for authentication when accessing the mission app from the local machine.

## Day 0 Deployment Instructions

1. Clone this repo locally.
2. Configure `zarf-config.yaml`, `tls.cert`, and `tls.key` with your environment-specific values. See above section for more details.
3. Run `make up`

## Day 2 Operations

TODO: write this section

## Maintenance

TODO: write this section
