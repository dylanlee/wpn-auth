This authentication solution has been created using AWS and will issue temporary tokens to whitelisted domains (for example: "noaa.gov" or "ua.edu") or specific whitelisted emails. The solution stores temporary tokens in a dynamoDB table and tokens are used to grant access to data stored in a private S3 bucket that is accessible by a cloudfront distribution that triggers token validation when a request is sent by a user.

## Things to keep in mind
In the variables.tf file make sure you have all the variables set (account id is empty) or you configure the variable when you run terraform. 

The private bucket variable name needs to be unique.

## Repository contents:
"auth.tf" this is a mostly working terraform version of the solution. I have to manually enable CORS on the api gateway for this version to work.

"auth_cloudformation.yaml": This is a cloudformation template file that outlines the resources, settings, and permissions needed to deploy the solution. It will do everything except setup simple email service (ses). SES needs to be setup by hand.


"accesslambda folder": This is the lambda function that grants tokens. 

"authlambda folder": This is the lambda function that does the authorizing. It is deployed to lambda@edge and triggered when someone visitis the cloudfront distribution that has the private S3 bucket as its origin.
