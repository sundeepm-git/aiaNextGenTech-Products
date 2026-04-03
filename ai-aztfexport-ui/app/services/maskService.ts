/**
 * Mask Service — Redacts Azure subscription IDs and resource group names
 * from display text for demo/external-facing purposes.
 *
 * Actual values are never modified when sent to the API — only the UI
 * display text is masked.
 */

// Regex for Azure subscription IDs (UUID format)
const SUBSCRIPTION_ID_RE =
  /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;

// Regex for resource group names that appear after keywords like
// "resource group", "resource_group", "resourceGroup", "rg:"
const RG_KEYWORD_RE =
  /(?<=(?:resource[\s_-]?group|resourceGroup|rg[\s:=])\s*)[A-Za-z0-9_-]{2,}/gi;

/**
 * Mask a subscription ID, showing only the first 4 and last 4 characters.
 * e.g. "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" → "d0f1****-****-****-****-********bca2"
 */
function maskSubscriptionId(id: string): string {
  const clean = id.replace(/-/g, '');
  // Show first 4 and last 4 hex chars, mask the rest
  const masked = clean.slice(0, 4) + '****-****-****-****-****' + clean.slice(-4);
  return masked;
}

/**
 * Mask a resource group name, showing only the first 3 characters.
 * e.g. "rg-mcp-servers" → "rg-***"
 */
function maskResourceGroup(name: string): string {
  if (name.length <= 3) return '***';
  return name.slice(0, 3) + '***';
}

/**
 * Mask all Azure subscription IDs and resource group names in the given text.
 * Returns the masked text for display purposes.
 */
export function maskSensitiveValues(text: string): string {
  // First mask subscription IDs
  let result = text.replace(SUBSCRIPTION_ID_RE, (match) => maskSubscriptionId(match));

  // Then mask resource group names that follow known keywords
  result = result.replace(RG_KEYWORD_RE, (match) => maskResourceGroup(match));

  return result;
}
