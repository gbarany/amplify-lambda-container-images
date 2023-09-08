Create a file named `container-secrets.yml` to automate the upload of secrets to the AWS SSM Parameter Store during the Amplify pre-push action. Installation of [`ssm-diff`](https://github.com/runtheops/ssm-diff) is required beforehand.

Format:
```
amplify:
  <AmplifyAppID>:
    <AmplifyEnvName>:
      <LambdaFunctionName>:
        DUMMY_SECRET: !secure 'Hello World'
```
Sample:
```
amplify:
  d16u77ru6fgbxt:
    dev:
      mybiglambda:
        DUMMY_SECRET1: !secure 'Hello World'
        DUMMY_SECRET2: !secure 'Hello World2'
      myotherlambda:
        OTHER_DUMMY_SECRET1: !secure 'Hello World'
        OTHER_DUMMY_SECRET2: !secure 'Hello World2'
```