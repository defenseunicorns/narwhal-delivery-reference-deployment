# On-Prem Lite Reference Deployment

Reference deployment for deploying a mission app integrated with Keycloak and DUBBD to a single-node K3s cluster.

## Components of this deployment

The following is a list of everything that goes into this deployment. Each item is separately deployed in the order listed.

1. Terraform root module that deploys one AWS EC2 instance. This component can be skipped if you already have a server you intend to deploy to.
2. Zarf Init Package
3. Zarf Package for MetalLB
4. Zarf Package for DUBBD
5. Zarf Package for IDAM (Keycloak)
6. Zarf Package for SSO (AuthService)
7. Zarf Package for the mission app. In this case, the simple Podinfo app is being used as a standin for the mission app.

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

Minimum requirements are:
- Access to an AWS account with the permissions to do things like create VPCs and EC2 instances and connect to instances using Session Manager
- AWS credentials configured locally using [environment variables](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html)
- `make`
- `docker`

Additional requirements if you want to be able to hit the cluster in a local browser window are:
- [sshuttle](https://github.com/sshuttle/sshuttle)
- `ssh`
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Session Manager Plugin for AWS CLI](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

## Objective

To have the mission app deployed and integrated with DUBBD and Keycloak in the single-node K3s cluster on the EC2 instance, and to be properly redirected to Keycloak for authentication when accessing the mission app from the local machine.

## Deployment Instructions

Follow these steps to deploy this reference deployment. These are the same steps that are run by the CI workflow in this repo. You do not need tools like Terraform or Zarf installed locally as everything runs in a Docker container that already has the tools installed. You should not need to customize anything in this repo to get it to work. If that is not the case, please open an issue.

> **WARNING:** This will modify your local /etc/hosts file. You should make a backup of that file before doing this in case something gets screwed up.

1. Clone this repo and `cd` into it

Then either:

2. Bring it all up with `sudo -E make on-prem-lite-up`

Or:

2. Initialize Terraform with `make on-prem-lite-terraform-init`
3. [Optional] Inspect the Terraform plan with `make on-prem-lite-terraform-plan`
4. Deploy the EC2 instance with `make on-prem-lite-terraform-apply`
5. Wait a couple of minutes for the instance to finish running its user data script
6. Create the K3s cluster and initialize Zarf with `make on-prem-lite-zarf-init`
7. Deploy MetalLB with `make on-prem-lite-deploy-metallb`
8. Deploy DUBBD with `make on-prem-lite-deploy-dubbd`
9. Deploy the IDAM package with `make on-prem-lite-deploy-idam`
10. Deploy the SSO package with `make on-prem-lite-deploy-sso`
11. Update the /etc/hosts file on the server with `make on-prem-lite-update-server-etc-hosts`
12. Update the /etc/hosts file on the local machine with `sudo -E make on-prem-lite-update-local-etc-hosts`
13. Update the CoreDNS configmap and restart the deployment with `make on-prem-lite-update-coredns-config`
13. Deploy the Mission App (Podinfo) with `make on-prem-lite-deploy-mission-app`

Then:

14. Run Sshuttle with `sudo -E make on-prem-lite-start-sshuttle`. This is a blocking command that will run until you CTRL-C it.
    > **NOTES:**
    > - Sshuttle is fickle. We've done our best to make it easy to use, but it is still a pain in the ass. Please open an issue in this repo if you have trouble with Sshuttle.
    > - Because `ssh` is used as the connection mechanism you will be prompted for the server's password. The password is "password". The password doesn't need to be changed and isn't a security issue if it gets out since the SSH port is not exposed and Session Manager is needed to connect to the server.
15. Open a browser and go to https://podinfo.bigbang.dev. If everything worked successfully it should redirect you and show the Keycloak login page. This concludes the guided deployment.

When you're done:

16. To teardown, run `sudo -E make on-prem-lite-down`.

## Notes

The following is some notes and a list of "gotchas" that frequently act as speedbumps when deploying stuff like this.

- When making the secret(s) that tell Pepr to configure AuthService to sit in front of an app, be sure that the base64 encoded values of the secrets do not contain trailing newlines. If they do, Pepr will not be able to parse the secret and will fail to deploy the app. A common method is to use `echo "<TheValue>" | base64` to base64 encode a secret, but doing this will add a trailing newline. Be sure to use `echo -n` to prevent the trailing newline from being added.
- To get Pepr to configure AuthService to sit in front of an app, the label `protect: keycloak` must be added to the pod(s). The most common/likely way to do this is in the Deployment manifest, in `spec.template.metadata.labels`. If this label is not present, Pepr will not configure AuthService to sit in front of the app.
- DUBBD requires TLSv1.3 or better. The versions of `curl` and `openssl` that are present in Amazon Linux 2 do not support TLSv1.3.
- Pepr needs to talk to Keycloak, but it doesn't support doing it internally. It wants to talk to Keycloak using https://keycloak.bigbang.dev. Because of that, we need to add a line to the CoreDNS ConfigMap and restart the CoreDNS deployment.
- If you want to log into the admin console in Keycloak, navigate to https://keycloak.bigbang.dev/auth/admin and use the credentials `admin`/`sup3r-secret-p@ssword`. NEVER USE THE DEFAULT PASSWORD IN NON-DEMO DEPLOYMENTS. The variable to change the password is `KC_ADM_PASSWORD` when deploying the `uds-idam` package.
