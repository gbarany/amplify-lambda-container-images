import json
import pandas as pd
import boto3
import logging
import os

ssm = boto3.client('ssm')

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Get secrets from SSM
parameter_names = ['DUMMY_SECRET']
basepath = f"/amplify/{os.environ.get('AMPLIFY_APP_ID')}/{os.environ.get('ENV')}/{os.environ.get('FUNCTION_NAME')}/"
response = ssm.get_parameters(
    Names=[basepath + parameter_name for parameter_name in parameter_names], WithDecryption=True)
secrets = {param['Name'].replace(basepath, ''): param['Value']
           for param in response['Parameters']}

def handler(event, context):
    logger.info("Hello SSM " + secrets['DUMMY_SECRET'])
    # Create a sample DataFrame
    df = pd.DataFrame({
        'name': ['Alice', 'Bob', 'Charlie'],
        'age': [25, 30, 35]
    })
    
    # Convert DataFrame to JSON
    df_json = df.to_json(orient='split')
    
    return {
        'statusCode': 200,
        'body': json.dumps(df_json)
    }
