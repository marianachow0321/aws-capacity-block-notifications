import boto3
import json
from datetime import datetime, timedelta, timezone
ec2 = boto3.client('ec2')
sns = boto3.client('sns')
sts = boto3.client('sts')

# Configuration
LOCAL_TIMEZONE_OFFSET = 8  # Hours offset from UTC

def lambda_handler(event, context):
    # Get account ID dynamically
    account_id = sts.get_caller_identity()['Account']
    region = boto3.Session().region_name
    
    # Get all capacity reservations
    response = ec2.describe_capacity_reservations()
    
    now = datetime.now()
    next_24_hours = now + timedelta(hours=24)
    
    for reservation in response['CapacityReservations']:
        if 'EndDate' in reservation:
            end_date = reservation['EndDate'].replace(tzinfo=None)
            
            # Check if expires within next 24 hours
            if now <= end_date <= next_24_hours:
                hours_remaining = int((end_date - now).total_seconds() / 3600)
                
                # Convert to UTC and local timezone
                end_date_utc = end_date.replace(tzinfo=timezone.utc)
                end_date_local = end_date_utc.astimezone(timezone(timedelta(hours=LOCAL_TIMEZONE_OFFSET)))
                
                message = f"""
Capacity Block Expiring Within 24 Hours!

Capacity Reservation ID: {reservation['CapacityReservationId']}
End Date (UTC): {end_date_utc.strftime('%Y-%m-%d %H:%M:%S UTC')}
End Date (+{LOCAL_TIMEZONE_OFFSET}): {end_date_local.strftime('%Y-%m-%d %H:%M:%S')} +{LOCAL_TIMEZONE_OFFSET:02d}:00
Hours Remaining: {hours_remaining}
Instance Type: {reservation['InstanceType']}
Instance Count: {reservation.get('TotalInstanceCount', 'N/A')}
Availability Zone: {reservation['AvailabilityZone']}
"""
                
                sns.publish(
                    TopicArn=f'arn:aws:sns:{region}:{account_id}:capacity-block-expiry-alerts',
                    Subject=f'AWS Account {account_id} Alert: Capacity Block Expiring in {hours_remaining} Hours',
                    Message=message
                )
    
    return {'statusCode': 200}
