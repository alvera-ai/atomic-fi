# Create Integration Test

Create a Vitest integration test for an API endpoint.

## Usage

```
/create-integration-test <resource_name>
```

**Arguments:**
- `$ARGUMENTS` - Resource name in snake_case (e.g., `users`, `tenants`, `api_keys`)

## Prerequisites

1. API endpoint exists with OpenAPI documentation
2. Client samples exist in `integration-tests/client-samples/{resources}/`
3. SDK is generated: `cd integration-tests && npm run generate:sdk`

## Instructions

### Step 1: Create Test File

Create `integration-tests/tests/{resources}.test.ts`:

```typescript
import { describe, it, expect, beforeAll } from 'vitest';
import { OpenAPI, AuthenticationService } from '@template/sdk';
import { createTenant } from '@template/client-samples/tenants/create';
// Import client samples for this resource
import { createResource } from '@template/client-samples/{resources}/create';
import { listResources } from '@template/client-samples/{resources}/list';
import { getResource } from '@template/client-samples/{resources}/show';
import { updateResource } from '@template/client-samples/{resources}/update';
import { deleteResource } from '@template/client-samples/{resources}/delete';

describe('Resource API Integration Tests', () => {
  let resourceId: string;
  let testTenantId: string;
  // Add other setup IDs as needed

  beforeAll(async () => {
    // Authenticate
    const authResponse = await AuthenticationService.sessionControllerCreate({
      requestBody: {
        email: process.env.ADMIN_EMAIL || 'admin@test.local',
        password: process.env.ADMIN_PASSWORD || 'TestPassword123!',
        tenant_slug: process.env.TENANT_SLUG || 'test-tenant',
      },
    }) as any;

    OpenAPI.TOKEN = authResponse.token;

    // Setup test data using client samples
    const tenant = await createTenant();
    testTenantId = tenant.id;
  });

  // === SUCCESS CASES (5 minimum) ===

  it('should create a resource (201)', async () => {
    const resource = await createResource(testTenantId);

    expect(resource).toBeDefined();
    expect(resource.id).toBeTruthy();
    resourceId = resource.id;
  });

  it('should list resources (200)', async () => {
    const response = await listResources();

    expect(response.data).toBeDefined();
    expect(Array.isArray(response.data)).toBe(true);
    expect(response.meta).toBeDefined();
  });

  it('should get a single resource (200)', async () => {
    const resource = await getResource(resourceId);

    expect(resource).toBeDefined();
    expect(resource.id).toBe(resourceId);
  });

  it('should update a resource (200)', async () => {
    const updated = await updateResource(resourceId, testTenantId);

    expect(updated).toBeDefined();
    expect(updated.id).toBe(resourceId);
  });

  it('should delete a resource (204)', async () => {
    await deleteResource(resourceId);

    // Verify deletion
    await expect(async () => {
      await getResource(resourceId);
    }).rejects.toThrow();
  });

  // === ERROR CASES (5 minimum) ===

  it('should return 422 for invalid create data', async () => {
    // Test with missing required fields
  });

  it('should return 404 for non-existent resource on show', async () => {
    // Test with random UUID
  });

  it('should return 422 for invalid update data', async () => {
    // Test with invalid field values
  });

  it('should return 404 for non-existent resource on update', async () => {
    // Test with random UUID
  });

  it('should return 404 for non-existent resource on delete', async () => {
    // Test with random UUID
  });
});
```

### Step 2: Run Tests

```bash
cd integration-tests

# Run specific test file
npm test -- tests/{resources}.test.ts

# Run with environment variables
ADMIN_EMAIL=admin@test.local \
ADMIN_PASSWORD='TestPassword123!' \
TENANT_SLUG=test-tenant \
npm test -- tests/{resources}.test.ts
```

### Step 3: Verify API Coverage (if Optic configured)

```bash
npm run api-coverage
```

## Test Patterns

### Testing 422 Validation Errors

```typescript
it('should return 422 for invalid create data', async () => {
  await expect(async () => {
    await ResourceService.resourceCreate({
      requestBody: {
        name: '', // Empty required field
        tenant_id: testTenantId,
      },
    });
  }).rejects.toThrow();
});
```

### Testing 404 Not Found

```typescript
it('should return 404 for non-existent resource', async () => {
  const randomId = crypto.randomUUID();

  await expect(async () => {
    await ResourceService.resourceShow({
      id: randomId,
    });
  }).rejects.toThrow();
});
```

### Testing Pagination

```typescript
it('should support pagination', async () => {
  // Create multiple resources
  await createResource(testTenantId);
  await createResource(testTenantId);
  await createResource(testTenantId);

  const response = await ResourceService.resourceList({
    page: 1,
    page_size: 2,
  }) as any;

  expect(response.data.length).toBe(2);
  expect(response.meta.total_count).toBeGreaterThanOrEqual(3);
});
```

## Post-Generation Checklist

After successfully creating integration tests, **update the implementation status**:

1. Open [guides/core-modules.md](../../guides/core-modules.md)
2. Update the status table for this context:
   - Mark **Vitest** as ✅ if integration tests are implemented and passing
   - Update the **Status** score (e.g., from 5/7 to 6/7)
3. Update the **Progress Summary** percentages for Vitest completion
4. Verify all tests pass: `cd integration-tests && npm test`

## Checklist

- [ ] Test file created in `integration-tests/tests/`
- [ ] Uses client samples (NOT direct SDK calls)
- [ ] 5+ success case tests
- [ ] 5+ error case tests
- [ ] All tests pass
- [ ] API coverage verified (if Optic configured)
- [ ] Implementation status updated in guides/core-modules.md
