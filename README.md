# Managing Custom Lambda Container Images with AWS Amplify

This repository provides a solution for managing custom Lambda container images as part of an AWS Amplify project. It addresses the limitation of the Amplify CLI, which currently doesn't support creating Lambda functions with custom container images out of the box.

Custom Lambda containers are useful in scenarios where you need more control over the runtime environment of your Lambda functions. This could be due to various reasons such as:

1. When the Lambda function has many dependent libraries that may exceed the file size limitation of Lambda Layers.
2. When the installation of other executable binaries is needed for the project.
3. When there is a need to build and test the Lambda function code on a local machine and then deploy the exact same environment to the AWS Lambda service.

In such scenarios, you can package your code and dependencies in a Docker image, and then use this image to create a Lambda function. This repository provides a blueprint for managing such custom Lambda container images as part of an AWS Amplify project.


## Onboarding a Custom Lambda

To include a new custom Lambda, adhere to these steps:

1. Create a new custom resource by running `amplify add custom`. This command creates a new resource in your Amplify project.

2. Modify the created CloudFormation template similar to [mybiglambda-cloudformation-template.json](https://github.com/gbarany/amplify-lambda-container-images-example/blob/main/amplify/backend/custom/mybiglambda/mybiglambda-cloudformation-template.json) provided in this repository. The key changes are in the `Resources` section where we define our Lambda function and its properties. This includes the function name, which is generated based on the `Amplify App ID` and the `function name`, and the `image URI`, which is generated based on the `ECR repository name` and `image tag`.

3. Create a new subfolder in the `containers` folder with the name of your Lambda function similar to `containers/mybiglambda`. This folder will contain your "Lambda-compatible" `Dockerfile` and any other dependencies needed for your function.

4. Add secrets to a file named `containers/container-secrets.yml`. This file is used to automate the upload of secrets to the AWS SSM Parameter Store during the Amplify pre-push hook. The secrets are defined in a specific format, with placeholders for the Amplify App ID, Amplify environment name, and Lambda function name.

```yaml
amplify:
  <AmplifyAppID>:
    <AmplifyEnvName>:
      <LambdaFunctionName>:
        DUMMY_SECRET: !secure 'Hello World'
```


5. Execute `amplify push` that kicks-off the custom lambda image build and deployment process, handled by the `containers/deploy.sh` script. This script performs several tasks:
- It creates an ECR repository for your Lambda function if it doesn't already exist.
- It builds and pushes a Docker image to the ECR repository.
- It increments a value called "next_tag" for each deployment. This ensures that each deployment uses a new Docker image.
- It updates the CloudFormation template with the correct values for the Amplify App ID, image tag, and repository name.


## Secrets Management

The repository provides a solution for secrets management using a tool called [ssm-diff](https://github.com/runtheops/ssm-diff). Secrets are defined in the `container-secrets.yml` file and uploaded to the AWS SSM Parameter Store during the Amplify pre-push hook. The upload process replaces placeholders in the secrets file with the actual `Amplify App ID`, uploads the secrets to the SSM Parameter Store, and then reverts the placeholders.

## Conclusion
This repository provides an opitionated blueprint for managing custom Lambda container images and secrets as part of an AWS Amplify project. It demonstrates how to leverage [Amplify Hooks](https://docs.amplify.aws/cli/project/command-hooks/) and custom [CloudFormation resources](https://docs.amplify.aws/cli/custom/cloudformation/) to overcome the limitations of the Amplify CLI.