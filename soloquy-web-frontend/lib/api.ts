export async function fetchHello(): Promise<string> {
  const apiUrl = process.env.API_URL;

  if (!apiUrl) {
    console.error("Error fetching hello endpoint: No backend configured.");
    return "No backend configured.";
  }

  try {
    const res = await fetch(`${apiUrl}/hello`, { cache: "no-store" });

    if (!res.ok) {
      throw new Error(`Backend returned status: ${res.status}.`);
    }

    const data = await res.json();
    return data.message ?? "Response did not contain a message.";
  } catch (error) {
    console.error("Error fetching hello endpoint:", error);
    return "Failed to load message from backend.";
  }
}
