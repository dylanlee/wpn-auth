// Importing SES and DynamoDB clients from AWS SDK v3
const { SESClient, SendEmailCommand } = require("@aws-sdk/client-ses");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient } = require("@aws-sdk/lib-dynamodb");
const dynamoDBClient = new DynamoDBClient({  region: "us-east-1" });
const docClient = DynamoDBDocumentClient.from(dynamoDBClient);
const { QueryCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const crypto = require('crypto');
const ses = new SESClient({ region: "us-east-1"});
const tableName = "TokenStorage";
const whitelistDomains = ['ua.edu', 'noaa.gov']; // Add your domains here
const whitelistEmails = ['dylanblee@gmail.com']; // Add specific emails here

exports.handler = async (event) => {
    try {
        const { email } = JSON.parse(event.body);
        if (!email || !validateEmail(email)) {
            return sendResponse(400, { message: 'Invalid email format or domain not allowed.' });
        }

        // Check existing tokens
        const tokensCount = await countRecentTokens(email);
        if (tokensCount >= 2) {
            return sendResponse(400, { message: 'Token limit reached. Only 2 tokens can be issued within 90 days.' });
        }

        const token = generateToken();
        const currentDate = new Date().toISOString();
	    //
	// Store in DynamoDB
	await docClient.send(new PutCommand({
	    TableName: tableName,
	    Item: { email, token, generationDate: currentDate }
	}));
        // Send email
        const emailSent = await sendEmail(email, token);

        return sendResponse(200, { message: 'Token generated and sent.', tokenSent: emailSent });
    } catch (error) {
        console.error('Error:', error);
        return sendResponse(500, { message: 'Internal server error' });
    }
};

async function countRecentTokens(email) {
    const ninetyDaysAgo = new Date(Date.now() - (90 * 24 * 60 * 60 * 1000)).toISOString();
    // Count recent tokens
    const result = await docClient.send(new QueryCommand({
	TableName: tableName,
	IndexName: 'EmailIndex', // Make sure to create this index on the 'email' attribute in your DynamoDB table
	KeyConditionExpression: 'email = :email and generationDate >= :ninetyDaysAgo',
	ExpressionAttributeValues: {
	    ':email': email,
	    ':ninetyDaysAgo': ninetyDaysAgo,
	}
    }));
    return result.Items.length;
}

function validateEmail(email) {
    const domain = email.split('@')[1];
    return whitelistDomains.includes(domain) || whitelistEmails.includes(email);
}

function generateToken() {
    return crypto.randomBytes(16).toString('hex');
}

async function sendEmail(recipientEmail, token) {
    // Send email
    try {
	await ses.send(new SendEmailCommand({
	    Source: 'dylan@enmote.com', // Replace with your "from" address
	    Destination: { ToAddresses: [recipientEmail] },
	    Message: {
		Subject: { Data: 'Your Access Token' },
		Body: {
		    Text: { Data: `Your token is: ${token}` }
		}
	    }
	}));
	return true;
    } catch (error) {
	console.error('Failed to send email:', error);
	return false;
    }

}

function sendResponse(statusCode, body) {
    return {
        statusCode: statusCode,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*', // This should be restricted to your domain in production
            'Access-Control-Allow-Credentials': true // If your client needs to send credentials
        },
        body: JSON.stringify(body)
    };
}


