/**
 * Blocklist Feature Demonstration
 *
 * This test demonstrates the blocklist screening feature that blocks
 * account holders with names matching the blocklist before calling
 * the Watchman sanctions screening API.
 */

import { test, expect } from '@playwright/test';

// Get API key from dev.exs (root_api_key)
const API_KEY = 'alvera_root_api_key_dev';

test.describe('Blocklist Screening Demo', () => {
  test('demonstrates blocklist blocking with exact match', async ({ page }) => {
    // Navigate to API documentation
    await page.goto('http://localhost:4000/api/docs');
    await page.waitForLoadState('networkidle');

    // Wait for page to fully load
    await page.waitForTimeout(2000);

    // Scroll to show the header
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(1000);

    // Click on Onboarding section
    await page.getByRole('button', { name: /onboarding/i }).click();
    await page.waitForTimeout(1500);

    // Scroll to show the endpoint
    await page.getByText('Screen account holder for onboarding').scrollIntoViewIfNeeded();
    await page.waitForTimeout(1500);

    // Now make a direct API call to demonstrate blocklist blocking
    console.log('\n=== Testing Blocklist Feature ===\n');

    // Test 1: Blocklisted first name "John"
    console.log('Test 1: Screening individual with blocklisted first name "John"...');
    const response1 = await page.request.post('http://localhost:4000/api/onboarding/screen', {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY
      },
      data: {
        name: 'Test Company',
        type: 'business',
        interested_individuals: [
          {
            first_name: 'John',
            last_name: 'Zephyrwind'
          }
        ],
        interested_companies: []
      }
    });

    const result1 = await response1.json();
    console.log('Response Status:', response1.status());
    console.log('Overall Status:', result1.overall_status);
    console.log('Entities Screened:', result1.total_entities_screened);
    console.log('Entities with Matches:', result1.entities_with_matches);

    if (result1.entity_decisions && result1.entity_decisions[0]) {
      const decision = result1.entity_decisions[0];
      console.log('\nEntity Decision:');
      console.log('  Entity Name:', decision.entity_name);
      console.log('  Screening Result:', decision.screening_result);
      console.log('  Watchman Matches:', decision.match_count);

      if (decision.blocklist_matches && decision.blocklist_matches.length > 0) {
        console.log('\n  Blocklist Matches:');
        decision.blocklist_matches.forEach((match: any, index: number) => {
          console.log(`    Match ${index + 1}:`);
          console.log(`      Term: "${match.matched_term}"`);
          console.log(`      Type: ${match.match_type}`);
          console.log(`      Scope: ${match.scope}`);
          console.log(`      Reason: ${match.reason}`);
        });
      }
    }

    // Assert that the individual was blocked
    expect(result1.overall_status).toBe('blocked');
    expect(result1.entity_decisions[0].screening_result).toBe('blocked');
    expect(result1.entity_decisions[0].blocklist_matches.length).toBeGreaterThan(0);
    expect(result1.entity_decisions[0].blocklist_matches[0].matched_term).toBe('john');
    expect(result1.entity_decisions[0].blocklist_matches[0].scope).toBe('first_name');

    await page.waitForTimeout(2000);

    // Test 2: Blocklisted company name "ACME"
    console.log('\n\nTest 2: Screening company with blocklisted name "ACME"...');
    const response2 = await page.request.post('http://localhost:4000/api/onboarding/screen', {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY
      },
      data: {
        name: 'Test Company',
        type: 'business',
        interested_individuals: [],
        interested_companies: [
          {
            name: 'ACME Corporation'
          }
        ]
      }
    });

    const result2 = await response2.json();
    console.log('Response Status:', response2.status());
    console.log('Overall Status:', result2.overall_status);
    console.log('Entities Screened:', result2.total_entities_screened);

    if (result2.entity_decisions && result2.entity_decisions[0]) {
      const decision = result2.entity_decisions[0];
      console.log('\nEntity Decision:');
      console.log('  Entity Name:', decision.entity_name);
      console.log('  Screening Result:', decision.screening_result);

      if (decision.blocklist_matches && decision.blocklist_matches.length > 0) {
        console.log('\n  Blocklist Matches:');
        decision.blocklist_matches.forEach((match: any, index: number) => {
          console.log(`    Match ${index + 1}:`);
          console.log(`      Term: "${match.matched_term}"`);
          console.log(`      Type: ${match.match_type}`);
          console.log(`      Scope: ${match.scope}`);
          console.log(`      Reason: ${match.reason}`);
        });
      }
    }

    // Assert that the company was blocked
    expect(result2.overall_status).toBe('blocked');
    expect(result2.entity_decisions[0].screening_result).toBe('blocked');
    expect(result2.entity_decisions[0].blocklist_matches.length).toBeGreaterThan(0);
    expect(result2.entity_decisions[0].blocklist_matches[0].matched_term).toBe('acme');
    expect(result2.entity_decisions[0].scope).toBe('company_name');

    await page.waitForTimeout(2000);

    // Test 3: Clean name that passes blocklist
    console.log('\n\nTest 3: Screening clean individual (should pass)...');
    const response3 = await page.request.post('http://localhost:4000/api/onboarding/screen', {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY
      },
      data: {
        name: 'Clean Company',
        type: 'business',
        interested_individuals: [
          {
            first_name: 'Alice',
            last_name: 'Wonderland'
          }
        ],
        interested_companies: []
      }
    });

    const result3 = await response3.json();
    console.log('Response Status:', response3.status());
    console.log('Overall Status:', result3.overall_status);
    console.log('Entities Screened:', result3.total_entities_screened);

    if (result3.entity_decisions && result3.entity_decisions[0]) {
      const decision = result3.entity_decisions[0];
      console.log('\nEntity Decision:');
      console.log('  Entity Name:', decision.entity_name);
      console.log('  Screening Result:', decision.screening_result);
      console.log('  Blocklist Matches:', decision.blocklist_matches?.length || 0);
      console.log('  Watchman Matches:', decision.match_count);
    }

    console.log('\n=== Blocklist Demo Complete ===\n');

    await page.waitForTimeout(2000);
  });
});
