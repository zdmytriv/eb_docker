#!/usr/bin/env python

from boto.s3.connection import S3Connection
from boto.s3.key import Key
from boto.utils import get_instance_identity
from sys import argv
from os import environ

environ['S3_USE_SIGV4'] = 'true'

def download_auth(bucket_name, key_name, region):
    host = 's3-%s.amazonaws.com' % region
    if region == 'us-east-1':
        host = 's3.amazonaws.com'
    if region == 'eu-central-1':
        host = 's3.eu-central-1.amazonaws.com'
    conn = S3Connection(host = host)
    bucket = conn.get_bucket(bucket_name, validate = False)
    key = Key(bucket = bucket, name = key_name)
    key.get_contents_to_filename('/root/.dockercfg')

if __name__ == '__main__':
    download_auth(argv[1], argv[2], get_instance_identity()['document']['region'])
