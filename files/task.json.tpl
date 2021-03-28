[
  {
    "name": "${service}",
    "image": "${container}",
    "cpu": 1024,
    "memory": 2048,
    "essential": true,
    "portMappings": [
      {
        "containerPort": 3000,
        "protocol": "tcp"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-stream-prefix": "ecs",
        "awslogs-region": "${region}",
        "awslogs-group": "${log_group}"
      }
    },
    "environment": [
      {"name": "AWS_REGION", "value": "${region}"},
      {"name": "ATHENS_STORAGE_TYPE", "value": "s3"},
      {"name": "ATHENS_S3_BUCKET_NAME", "value": "${bucket}"},
      {"name": "AWS_USE_DEFAULT_CONFIGURATION", "value": "true"},
      {"name": "ATHENS_GONOSUM_PATTERNS", "value": "${gonosum}"},
      {"name": "ATHENS_GO_BINARY_ENV_VARS", "value": "${go_env_vars"}
    ]
  }
]