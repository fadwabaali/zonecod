import { requireRole } from "@/lib/auth/require-role";
import { LogoutButton } from "@/components/auth/logout-button";

export default async function SellerLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireRole("seller");

  return (
    <div className="min-h-screen">
      <header className="flex items-center justify-between border-b border-slate-200 bg-white px-6 py-3">
        <span className="text-sm font-semibold text-text-muted">
          ZONECOD Seller
        </span>
        <LogoutButton />
      </header>
      <main>{children}</main>
    </div>
  );
}