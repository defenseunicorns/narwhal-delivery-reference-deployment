# On-Prem Lite Reference Deployment

Reference deployment for deploying a mission app integrated with Keycloak and DUBBD to a single-node K3s cluster.

## Components of this deployment

The following is a list of everything that goes into this deployment. Each item is separately deployed in the order listed.

1. Terraform root module that deploys one AWS EC2 instance. This component can be skipped if you already have a server you intend to deploy to.
2. Zarf Init Package
3. Zarf Package for MetalLB
3. Zarf Package for DUBBD
4. Zarf Package for IDAM (Keycloak)
5. Zarf Package for SSO (AuthService)
5. Zarf Package for the mission app. In this case, the simple Podinfo app is being used as a standin for the mission app.

## Prerequisites

- Access to an AWS account with the permissions to do things like create VPCs and EC2 instances and connect to instances using Session Manager
- AWS credentials configured locally using [environment variables](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html)
- `make`
- `docker`

## Deployment Instructions

Follow these steps to deploy this reference deployment. These are the same steps that are run by the CI workflow in this repo. You do not need tools like Terraform or Zarf installed locally as everything runs in a Docker container that already has the tools installed. You should not need to customize anything in this repo to get it to work. If that is not the case, please open an issue.

1. Clone this repo and `cd` into it
2. Initialize Terraform with `make on-prem-lite-terraform-init`
3. [Optional] Inspect the Terraform plan with `make on-prem-lite-terraform-plan`
4. Deploy the EC2 instance with `make on-prem-lite-terraform-apply`
5. Wait a couple of minutes for the instance to finish running its user data script
6. Create the K3s cluster and initialize Zarf with `make on-prem-lite-zarf-init`
7. Deploy MetalLB with `make on-prem-lite-deploy-metallb`
8. Deploy DUBBD with `make on-prem-lite-deploy-dubbd`
9. ...todo
