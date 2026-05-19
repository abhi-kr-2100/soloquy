import "server-only";

import { getVercelOidcToken } from "@vercel/oidc";
import { ExternalAccountClient, Impersonated } from "google-auth-library";

async function getGcpIdToken(audience: string): Promise<string> {
  const provider = process.env.GCP_WORKLOAD_IDENTITY_PROVIDER;
  const serviceAccount = process.env.GCP_SERVICE_ACCOUNT_EMAIL;
  if (!provider) {
    throw new Error("GCP_WORKLOAD_IDENTITY_PROVIDER environment variable is missing.");
  }
  if (!serviceAccount) {
    throw new Error("GCP_SERVICE_ACCOUNT_EMAIL environment variable is missing.");
  }

  const vercelOidcToken = await getVercelOidcToken();
  if (!vercelOidcToken) {
    throw new Error("Failed to retrieve Vercel OIDC token.");
  }

  const sourceClient = ExternalAccountClient.fromJSON({
    type: "external_account",
    audience: `//iam.googleapis.com/${provider}`,
    subject_token_type: "urn:ietf:params:oauth:token-type:jwt",
    token_url: "https://sts.googleapis.com/v1/token",
    subject_token_supplier: {
      getSubjectToken: async () => vercelOidcToken,
    },
  });

  if (!sourceClient) {
    throw new Error("Failed to initialize Google ExternalAccountClient.");
  }

  const impersonatedClient = new Impersonated({
    sourceClient,
    targetPrincipal: serviceAccount,
  });

  const idToken = await impersonatedClient.fetchIdToken(audience);
  if (!idToken) {
    throw new Error("GCP ID Token is empty.");
  }

  return idToken;
}

export async function fetchWithAuth(url: string | URL, init?: RequestInit): Promise<Response> {
  if (process.env.NODE_ENV === "development" || process.env.NODE_ENV === "test") {
    return fetch(url, init);
  }

  const audience = new URL(url.toString()).origin;
  const idToken = await getGcpIdToken(audience);

  const headers = new Headers(init?.headers);
  headers.set("Authorization", `Bearer ${idToken}`);

  return fetch(url, { ...init, headers });
}
