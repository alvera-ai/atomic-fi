const BACKEND_ORIGIN = "http://localhost:4100";

export async function getEmbedToken(bearer: string): Promise<string> {
  const res = await fetch("/api/lotus/embed-token", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${bearer}`,
    },
  });
  if (!res.ok) {
    throw new Error(`getEmbedToken: ${res.status} ${await res.text()}`);
  }
  const body = (await res.json()) as { token: string };
  return body.token;
}

export function embedUrl(token: string): string {
  return `${BACKEND_ORIGIN}/lotus?token=${encodeURIComponent(token)}`;
}
