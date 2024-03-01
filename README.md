This authentication solution has been created using AWS and will issue temporary tokens to whitelisted domains (for example: "noaa.gov" or "ua.edu") or specific whitelisted emails. The solution stores temporary tokens in a dynamoDB table and tokens are used to grant access to data stored in a private S3 bucket that is accessible by a cloudfront distribution that triggers token validation when a request is sent by a user.

Repository contents:

"authcfcurrent.yaml": This is a cloudformation template file that outlines the resources, settings, and permissions needed to deploy the solution. It will do everything except setup simple email service (ses). SES needs to be setup by hand.

"accesslambda folder": This is the lambda function that grants tokens. 

"authlambda folder": This is the lambda function that does the authorizing. It is deployed to lambda@edge and triggered when someone visitis the cloudfront distribution that has the private S3 bucket as its origin.
