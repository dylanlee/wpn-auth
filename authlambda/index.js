// Importing SES and DynamoDB clients from AWS SDK v3
const { SESClient, SendEmailCommand } = require("@aws-sdk/client-ses");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient } = require("@aws-sdk/lib-dynamodb");
const dynamoDBClient = new DynamoDBClient({  region: "us-east-1" });
const docClient = DynamoDBDocumentClient.from(dynamoDBClient);
const { QueryCommand, PutCommand, DeleteCommand } = require("@aws-sdk/lib-dynamodb");
const crypto = require('crypto');
const ses = new SESClient({ region: "us-east-1"});
const tableName = "TokenStorage";
const fs = require('fs');
const path = require('path');

exports.handler = async (event) => {
    //load whitelist
    const whitelist = await loadWhitelist();
    const whitelistDomains = whitelist.domains;
    const whitelistEmails = whitelist.emails;

    try {
        const { email } = JSON.parse(event.body);
        if (!email || !validateEmail(email, whitelistDomains, whitelistEmails)) {
            return sendResponse(400, { message: 'Invalid email format or domain not allowed.' });
        }

        // Check existing tokens
        const tokensCount = await countRecentTokens(email);
        if (tokensCount >= 2) {
            return sendResponse(400, { message: 'Token limit reached. Only 2 tokens can be issued within 90 days.' });
        }

        const token = generateToken();
        const currentDate = new Date();
        const expiryDate = new Date(currentDate.getTime() + (91 * 24 * 60 * 60 * 1000)); // 91 days from now

        // Convert expiryDate to Unix epoch time in seconds
        const timeToExist = Math.floor(expiryDate.getTime() / 1000);
	    
	    // Store in DynamoDB
	    await docClient.send(new PutCommand({
	        TableName: tableName,
	        Item: { email, token, generationDate: currentDate.toISOString(), TimeToExist: timeToExist }
	    }));
        // Send email
        const emailSent = await sendEmail(email, token);

        return sendResponse(200, { message: 'Token generated and sent.', tokenSent: emailSent });
    } catch (error) {
        console.error('Error:', error);
        return sendResponse(500, { message: 'Internal server error' });
    }
};

async function loadWhitelist() {
    const whitelistPath = path.join(__dirname, 'whitelist'); // Adjust if your file is in a subdirectory
    return new Promise((resolve, reject) => {
        fs.readFile(whitelistPath, 'utf8', (err, data) => {
            if (err) {
                console.error('Error reading whitelist file:', err);
                return reject(err);
            }
            try {
                const whitelist = JSON.parse(data);
                return resolve(whitelist);
            } catch (parseError) {
                console.error('Error parsing whitelist file:', parseError);
                return reject(parseError);
            }
        });
    });
}

async function countRecentTokens(email) {
    const ninetyDaysAgo = new Date(Date.now() - (90 * 24 * 60 * 60 * 1000)).toISOString();
    // Count recent tokens
    const result = await docClient.send(new QueryCommand({
	TableName: tableName,
	IndexName: 'EmailIndex', 
	KeyConditionExpression: 'email = :email and generationDate >= :ninetyDaysAgo',
	ExpressionAttributeValues: {
	    ':email': email,
	    ':ninetyDaysAgo': ninetyDaysAgo,
	}
    }));
    return result.Items.length;
}


function validateEmail(email, whitelistDomains, whitelistEmails) {
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
	    Source: 'dylan@waternode.ciroh.org',
	    Destination: { ToAddresses: [recipientEmail] },
	    Message: {
		Subject: { Data: 'Your Water Prediction Node Access Token' },
		Body: {
		  Text: {
		    Data: `Greetings from the Water Prediction Node!\n\nYour token is: ${token}\n\nThis token is good for 90 days and can be used to access the Water Prediction Node experimental data catalog using python and the pystac library or the experimental catalog browser at https://waternode.ciroh.org/shhcat` 
		  }
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


