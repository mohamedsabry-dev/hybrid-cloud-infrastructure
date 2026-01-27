Created 4 Assume Rules

# AWS IAM OIDC Provider
An OpenID Connect (OIDC) provider is an entity that can authenticate users using the OIDC protocol. In AWS, you can create an IAM OIDC provider to allow your AWS resources to trust an external identity provider for authentication.

Setup with Github by AWS Cosole 
1. Sign in to the AWS Management Console and open the IAM console at https://console.aws.amazon.com/iam/.
2. In the navigation pane, choose "Identity providers", then choose "Add provider".
3. For "Provider Type", choose "OpenID Connect".
4. For "Provider URL", enter the URL of the OIDC provider (e.g., https://token.actions.githubusercontent.com for GitHub Actions).
5. For "Audience", enter the audience value that your OIDC provider uses (e.g
., sts.amazonaws.com for GitHub Actions).
6. Choose "Add provider" to create the OIDC provider.
7. Confirm Thumbprints , you can get it by running the following command:
   ```bash
   echo | openssl s_client -servername token.actions.githubusercontent.com -showcerts -connect token.actions.githubusercontent.com:443 2>/dev/null | openssl x509 -fingerprint -noout | sed 's/://g' | cut -d'=' -f2
   ```
8. After creating the OIDC provider, you can create IAM roles that trust this provider for authentication.

# Created 4 IAM Rules for trusting OIDC Provider
As mentioned in /roles folder, we have created 4 IAM roles with different permissions. Also Created 5 Policies as in /policies folder.


