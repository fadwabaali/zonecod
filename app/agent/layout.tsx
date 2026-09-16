import { requireRole } from "@/lib/auth/require-role";
import { LogoutButton } from "@/components/auth/logout-button";

export default async function AgentLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireRole("agent");

  return (
    <div className="min-h-screen">
      <header className="flex items-center justify-between border-b border-slate-200 bg-white px-6 py-3">
        <span className="text-sm font-semibold text-text-muted">
          ZONECOD Agent
        </span>
        <LogoutButton />
      </header>
      <main>{children}</main>
    </div>
  );
}