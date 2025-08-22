# Portainer API Documentation

This document provides comprehensive documentation for Portainer CE v2.33.0 API endpoints, specifically focusing on stack management operations used in the Docker Backup Manager.

## Table of Contents

1. [API Overview](#api-overview)
2. [Authentication](#authentication)
3. [Stack Endpoints](#stack-endpoints)
4. [Container Management](#container-management)
5. [Endpoint Management](#endpoint-management)
6. [Error Handling](#error-handling)
7. [Best Practices](#best-practices)
8. [Examples](#examples)

## API Overview

The Portainer API provides programmatic access to all Portainer functionality, allowing you to automate Docker stack deployment, management, and monitoring operations.

### Base URL Structure
```
http://localhost:9000/api          # Local API access
https://portainer.domain.com/api   # Remote HTTPS access
```

### API Documentation Sources
- **Official Documentation**: [docs.portainer.io/api](https://docs.portainer.io/api)
- **SwaggerHub**: [Portainer CE v2.33.0](https://app.swaggerhub.com/apis/portainer/portainer-ce/2.33.0)
- **Interactive Docs**: Available at `https://your-portainer-url/#!/api/docs`

## Authentication

### 1. Admin Initialization (First-time Setup)

Initialize the admin user account:

```bash
curl -X POST "http://localhost:9000/api/users/admin/init" \
  -H "Content-Type: application/json" \
  -d '{
    "Username": "admin@domain.com",
    "Password": "AdminPassword123!"
  }'
```

**Response**: Returns user object with admin user details.

### 2. Authentication (Get JWT Token)

Authenticate to get a JWT token:

```bash
curl -X POST "http://localhost:9000/api/auth" \
  -H "Content-Type: application/json" \
  -d '{
    "Username": "admin@domain.com",
    "Password": "AdminPassword123!"
  }'
```

**Response**:
```json
{
  "jwt": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### 3. Using JWT Token

Include the JWT token in the Authorization header for all subsequent requests:

```bash
curl -H "Authorization: Bearer <jwt_token>" \
  "http://localhost:9000/api/stacks"
```

### 4. Access Tokens (Alternative)

For long-term API access, create access tokens:

1. Log into Portainer UI
2. Go to "My account" → "Access tokens"
3. Create new token
4. Use in requests:

```bash
curl -H "X-API-Key: <access_token>" \
  "http://localhost:9000/api/stacks"
```

## Stack Endpoints

### 1. List Stacks

**Endpoint**: `GET /api/stacks`

List all stacks accessible to the authenticated user.

```bash
curl -H "Authorization: Bearer $JWT_TOKEN" \
  "http://localhost:9000/api/stacks"
```

**Response**:
```json
[
  {
    "Id": 1,
    "Name": "nginx-proxy-manager",
    "Type": 2,
    "EndpointId": 1,
    "SwarmId": "",
    "EntryPoint": "docker-compose.yml",
    "Env": [],
    "Status": 1,
    "CreationDate": 1692123456,
    "CreatedBy": "admin",
    "UpdateDate": 1692123456,
    "UpdatedBy": "admin",
    "ProjectPath": "/data/compose/nginx-proxy-manager",
    "AdditionalFiles": [],
    "AutoUpdate": null,
    "Option": null,
    "GitConfig": null,
    "FromAppTemplate": false
  }
]
```

### 2. Inspect Stack

**Endpoint**: `GET /api/stacks/{id}`

Get detailed information about a specific stack.

```bash
curl -H "Authorization: Bearer $JWT_TOKEN" \
  "http://localhost:9000/api/stacks/1"
```

**Response**: Returns detailed stack configuration including environment variables, Git config, and metadata.

### 3. Get Stack File Content

**Endpoint**: `GET /api/stacks/{id}/file`

Retrieve the Docker Compose file content for a stack.

```bash
curl -H "Authorization: Bearer $JWT_TOKEN" \
  "http://localhost:9000/api/stacks/1/file"
```

**Response**:
```json
{
  "StackFileContent": "version: '3.8'\nservices:\n  nginx-proxy-manager:\n    image: 'jc21/nginx-proxy-manager:latest'\n    ..."
}
```

### 4. Create Stack

**Endpoint**: `POST /api/stacks/create/standalone/string`

Create a new Docker Compose stack from string content.

```bash
curl -X POST "http://localhost:9000/api/stacks/create/standalone/string?endpointId=1" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "method": "string",
    "type": "standalone",
    "Name": "my-stack",
    "StackFileContent": "version: '\''3.8'\''\nservices:\n  web:\n    image: nginx:latest",
    "Env": [
      {
        "name": "ENV_VAR",
        "value": "value"
      }
    ]
  }'
```

**Parameters**:
- `endpointId`: Docker environment ID (usually 1 for local)
- `method`: "string" for inline content
- `type`: "standalone" for Docker Compose

### 5. Update Stack

**Endpoint**: `PUT /api/stacks/{id}`

Update an existing stack configuration.

```bash
curl -X PUT "http://localhost:9000/api/stacks/1?endpointId=1" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "StackFileContent": "version: '\''3.8'\''\nservices:\n  web:\n    image: nginx:alpine",
    "Env": [],
    "Prune": false
  }'
```

**Query Parameters**:
- `endpointId`: Docker environment ID (required, usually 1 for local)

**Payload Parameters**:
- `StackFileContent`: Updated Docker Compose YAML
- `Env`: Array of environment variables
- `Prune`: Remove orphaned containers (boolean)

### 6. Start Stack

**Endpoint**: `POST /api/stacks/{id}/start`

Start all containers in a stack.

```bash
curl -X POST "http://localhost:9000/api/stacks/1/start?endpointId=1" \
  -H "Authorization: Bearer $JWT_TOKEN"
```

**Parameters**:
- `endpointId`: Docker environment ID (required, usually 1 for local)

### 7. Stop Stack

**Endpoint**: `POST /api/stacks/{id}/stop`

Stop all containers in a stack.

```bash
curl -X POST "http://localhost:9000/api/stacks/1/stop?endpointId=1" \
  -H "Authorization: Bearer $JWT_TOKEN"
```

**Parameters**:
- `endpointId`: Docker environment ID (required, usually 1 for local)

### 8. Delete Stack

**Endpoint**: `DELETE /api/stacks/{id}`

Delete a stack and optionally its volumes.

```bash
curl -X DELETE "http://localhost:9000/api/stacks/1?external=false&endpointId=1" \
  -H "Authorization: Bearer $JWT_TOKEN"
```

**Parameters**:
- `external`: Delete external volumes (boolean)
- `endpointId`: Docker environment ID

## Container Management

### 1. List Containers (via Docker API)

**Endpoint**: `GET /api/endpoints/{endpointId}/docker/v1.41/containers/json`

List all containers through Portainer's Docker API proxy.

```bash
curl -H "Authorization: Bearer $JWT_TOKEN" \
  "http://localhost:9000/api/endpoints/1/docker/v1.41/containers/json?all=true"
```

**Parameters**:
- `all=true`: Include stopped containers
- `filters`: JSON-encoded filters

### 2. Stop Container

**Endpoint**: `POST /api/endpoints/{endpointId}/docker/v1.41/containers/{id}/stop`

Stop a specific container.

```bash
curl -X POST "http://localhost:9000/api/endpoints/1/docker/v1.41/containers/$CONTAINER_ID/stop" \
  -H "Authorization: Bearer $JWT_TOKEN"
```

### 3. Start Container

**Endpoint**: `POST /api/endpoints/{endpointId}/docker/v1.41/containers/{id}/start`

Start a specific container.

```bash
curl -X POST "http://localhost:9000/api/endpoints/1/docker/v1.41/containers/$CONTAINER_ID/start" \
  -H "Authorization: Bearer $JWT_TOKEN"
```

## Endpoint Management

### 1. List Endpoints

**Endpoint**: `GET /api/endpoints`

List all Docker environments.

```bash
curl -H "Authorization: Bearer $JWT_TOKEN" \
  "http://localhost:9000/api/endpoints"
```

### 2. Create Local Endpoint

**Endpoint**: `POST /api/endpoints`

Create a local Docker socket endpoint.

```bash
curl -X POST "http://localhost:9000/api/endpoints" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -F "Name=local" \
  -F "EndpointCreationType=1" \
  -F "URL=" \
  -F "PublicURL=" \
  -F "TagIds=[]" \
  -F "ContainerEngine=docker"
```

## Error Handling

### Common HTTP Status Codes

- **200 OK**: Successful request
- **201 Created**: Resource created successfully
- **204 No Content**: Successful request with no response body
- **400 Bad Request**: Invalid request parameters
- **401 Unauthorized**: Authentication required or failed
- **403 Forbidden**: Insufficient permissions
- **404 Not Found**: Resource not found
- **409 Conflict**: Resource already exists
- **500 Internal Server Error**: Server error

### Error Response Format

```json
{
  "message": "Stack not found",
  "details": "Stack with identifier 999 not found inside environment 1"
}
```

### Best Practices for Error Handling

1. **Check API Availability**:
```bash
curl -s "http://localhost:9000/api/status" >/dev/null 2>&1 || {
    echo "Portainer API not available"
    exit 1
}
```

2. **Validate JWT Token**:
```bash
jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
if [[ -z "$jwt_token" ]]; then
    echo "Authentication failed"
    exit 1
fi
```

3. **Parse JSON Responses**:
```bash
if echo "$response" | jq -e . >/dev/null 2>&1; then
    echo "Valid JSON response"
else
    echo "Invalid JSON: $response"
fi
```

## Best Practices

### 1. Authentication Management

- Use JWT tokens for short-term operations
- Use access tokens for long-term automation
- Implement token refresh logic for long-running processes
- Store credentials securely (e.g., in protected files with 600 permissions)

### 2. API Request Patterns

- Always validate JSON responses before processing
- Implement retry logic for transient failures
- Use appropriate timeouts for requests
- Handle rate limiting gracefully

### 3. Stack Management

- Capture complete stack state before modifications
- Use atomic operations where possible
- Implement rollback mechanisms for critical operations
- Validate stack deployment after changes

### 4. Error Recovery

- Implement graceful fallbacks when API is unavailable
- Provide clear error messages with recovery suggestions
- Log detailed error information for troubleshooting
- Create recovery checkpoints for complex operations

## Examples

### Complete Backup Workflow

```bash
#!/bin/bash

# 1. Authenticate
JWT_TOKEN=$(curl -s -X POST "http://localhost:9000/api/auth" \
  -H "Content-Type: application/json" \
  -d '{"Username":"admin@domain.com","Password":"AdminPassword123!"}' | \
  jq -r '.jwt')

# 2. Get all stacks
STACKS=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" \
  "http://localhost:9000/api/stacks")

# 3. Process each stack
echo "$STACKS" | jq -c '.[]' | while read -r stack; do
    STACK_ID=$(echo "$stack" | jq -r '.Id')
    STACK_NAME=$(echo "$stack" | jq -r '.Name')
    
    # Get detailed stack info
    STACK_DETAIL=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" \
      "http://localhost:9000/api/stacks/$STACK_ID")
    
    # Get stack file content
    STACK_FILE=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" \
      "http://localhost:9000/api/stacks/$STACK_ID/file")
    
    # Save stack configuration
    echo "$STACK_DETAIL" > "backup_${STACK_NAME}_config.json"
    echo "$STACK_FILE" > "backup_${STACK_NAME}_compose.json"
    
    # Stop stack for backup
    curl -s -X POST "http://localhost:9000/api/stacks/$STACK_ID/stop?endpointId=1" \
      -H "Authorization: Bearer $JWT_TOKEN"
done
```

### Stack Restoration Workflow

```bash
#!/bin/bash

# Restore stacks from backup
for config_file in backup_*_config.json; do
    STACK_NAME=$(basename "$config_file" _config.json | sed 's/backup_//')
    COMPOSE_FILE="${config_file/_config/_compose}"
    
    if [[ -f "$COMPOSE_FILE" ]]; then
        # Extract stack file content
        STACK_CONTENT=$(jq -r '.StackFileContent' "$COMPOSE_FILE")
        
        # Create/update stack
        curl -X POST "http://localhost:9000/api/stacks/create/standalone/string?endpointId=1" \
          -H "Authorization: Bearer $JWT_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{
            \"method\": \"string\",
            \"type\": \"standalone\",
            \"Name\": \"$STACK_NAME\",
            \"StackFileContent\": $(echo "$STACK_CONTENT" | jq -Rs .),
            \"Env\": []
          }"
    fi
done
```

### Health Check and Monitoring

```bash
#!/bin/bash

# Check Portainer API health
check_portainer_health() {
    if curl -s "http://localhost:9000/api/status" >/dev/null 2>&1; then
        echo "✓ Portainer API is healthy"
        return 0
    else
        echo "✗ Portainer API is not responding"
        return 1
    fi
}

# Check stack status
check_stack_status() {
    local stack_id="$1"
    local stack_info
    
    stack_info=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" \
      "http://localhost:9000/api/stacks/$stack_id")
    
    local status
    status=$(echo "$stack_info" | jq -r '.Status // "unknown"')
    
    case "$status" in
        1) echo "✓ Stack is running" ;;
        2) echo "⚠ Stack is stopped" ;;
        *) echo "? Stack status unknown ($status)" ;;
    esac
}
```

## Integration with Docker Backup Manager

The Docker Backup Manager uses these API endpoints in the following workflow:

1. **Authentication**: Initialize admin user and authenticate for JWT tokens
2. **Stack Discovery**: List all stacks and capture detailed configurations
3. **Graceful Shutdown**: Stop containers via API before backup
4. **Configuration Capture**: Save stack states with complete metadata
5. **Service Management**: Start/stop stacks during backup/restore operations
6. **Validation**: Verify stack deployment and container status

This comprehensive API usage ensures reliable, API-driven backup and restore operations that maintain complete stack state consistency.