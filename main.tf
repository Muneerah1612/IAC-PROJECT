terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-west-2"
}
data "archive_file" "lambda_zip_inline" {
  type        = "zip"
  output_path = "/tmp/lambda_zip_inline.zip"
  source {
    content  = <<EOF
        module.exports.handler = async (event, context, callback) => {
	        const what = "world";
	        const response = `Hello $${what}!`;
	        callback(null, response);
            };
  EOF
    filename = "main.js"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "lambda_exec"
  path               = "/"
  description        = "Allows Lambda Function to call AWS services."
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}
resource "aws_iam_role" "stepfunc_role" {
  name = "stepfunc_exec"
  path = "/"
  description = "Allows Step functions to call Lambda function"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "states.amazonaws.com"
            },
            "Action": "sts:AssumeRole",
            "Sid": "StateFunctionAssumeRole"
        }
    ]

}
EOF
}
resource "aws_lambda_function" "lambda_zip_inline" {
  filename = data.archive_file.lambda_zip_inline.output_path
  source_code_hash = data.archive_file.lambda_zip_inline.output_base64sha256
  runtime = "nodejs12.x"
handler = "main.handler"
role = aws_iam_role.lambda_exec_role.arn
reserved_concurrent_executions = 2
function_name = "tflambda_function"
tracing_config {
mode = "Active"
}
}

resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "lambda_step_function"
  role_arn = aws_iam_role.stepfunc_role.arn

  definition = <<EOF
  {
    "Comment": "Invoke AWS Lambda from AWS Step Functions with Terraform",
    "StartAt": "Hello",
    "States": {
      "Hello": {
        "Type": "Pass",
        "Next": "FirstStepFunction"
    },
    "FirstStepFunction": {
        "Type": "Task",
        "Resource": "${aws_lambda_function.lambda_zip_inline.arn}",
        "End": true
    }
        
    }
  }
  EOF
}