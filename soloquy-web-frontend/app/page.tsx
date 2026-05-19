import { fetchHello } from "@/lib/api";

export const dynamic = "force-dynamic";

export default async function Home() {
  const message = await fetchHello();

  return (
    <main>
      {message}
    </main>
  );
}
