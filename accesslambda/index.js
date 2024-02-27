// Importing necessary clients and commands from AWS SDK v3
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, QueryCommand } = require("@aws-sdk/lib-dynamodb");

// Initialize the DynamoDB Document Client
const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({region: "us-east-1"}));
const tableName = "TokenStorage";

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    
    // Check if it's an OPTIONS request and handle accordingly
    if (request.method === 'OPTIONS') {
        return generateResponse(request, 204, 'OK');
    }

    try {
        // Extract the token from the request headers
        const tokenHeader = request.headers['authorization'];
        if (!tokenHeader) {
            // Deny access if no authorization header is present
            return generateResponse(request, 401, 'Unauthorized: No token provided');
        }
        const token = tokenHeader[0].value;

        // Validate the token
        const tokenValid = await validateToken(token);
        if (!tokenValid) {
            // Deny access if the token is invalid
            return generateResponse(request, 403, 'Forbidden: Invalid or expired token');
        }

        // If the token is valid, allow the request to proceed
        return request;
    } catch (error) {
        console.error('Error:', error);
        // Optionally, you might want to return a 500 error for server errors
        // But in many cases, it's better to not expose internal server errors directly
        // Instead, you could log the error and return a generic 403 or 401 error
        return generateResponse(request, 403, 'Access denied',);
    }
};

async function validateToken(token) {
    const currentDate = new Date();
    const ninetyDaysAgo = new Date(currentDate.getTime() - (90 * 24 * 60 * 60 * 1000));

    const command = new QueryCommand({
        TableName: "TokenStorage",
        KeyConditionExpression: '#token = :tokenVal',
        ExpressionAttributeNames: {
            '#token': 'token',
        },
        ExpressionAttributeValues: {
            ':tokenVal': token,
        },
    });

    try {
        const { Items } = await docClient.send(command);
        if (Items.length === 0) {
            return false;
        }

        // Assuming generationDate is stored as a string in ISO 8601 format
        const tokenGenerationDate = new Date(Items[0].generationDate);

        // Check if the token's generation date is after the calculated date 90 days ago
        if (tokenGenerationDate >= ninetyDaysAgo) {
            return true; // Token is valid
        } else {
            return false; // Token is older than 90 days and thus invalid
        }
    } catch (error) {
        console.error("Error querying tokens:", error);
        throw error;
    }
}


function generateResponse(request, status, statusText) {
    // Check if it's an OPTIONS request and generate appropriate headers
    const isOptionsRequest = request.method === 'OPTIONS';
    let headers;

    if (isOptionsRequest) {
        headers = {
            'access-control-allow-origin': [{
                key: 'Access-Control-Allow-Origin',
                value: '*' // Or specify your domain
            }],
            'access-control-allow-methods': [{
                key: 'Access-Control-Allow-Methods',
                value: 'GET, OPTIONS'
            }],
            'access-control-allow-headers': [{
                key: 'Access-Control-Allow-Headers',
                value: 'Authorization'
            }],
            'access-control-max-age': [{
                key: 'Access-Control-Max-Age',
                value: '86400' // 24 hours
            }]
        };
    } else {
        headers = {
            'content-type': [{
                key: 'Content-Type',
                value: 'text/plain'
            }]
        };
    }

    return {
        status: isOptionsRequest ? '204' : status.toString(),
        statusDescription: statusText,
        headers: headers,
        body: isOptionsRequest ? '' : statusText
    };
}


