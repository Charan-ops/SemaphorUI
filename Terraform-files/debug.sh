#!/bin/bash

whoami

echo "HOME=$HOME"

pwd

echo "===== HOME ====="
ls -la ~

echo "===== AWS ====="
ls -la ~/.aws

echo "===== AWS Config ====="
cat ~/.aws/config

echo "===== AWS Credentials ====="
cat ~/.aws/credentials

echo "===== AWS Environment ====="
env | grep AWS

echo "===== AWS CLI ====="
aws configure list

echo "===== Terraform ====="
terraform version