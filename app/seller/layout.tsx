import { requireRole } from "@/lib/auth/require-role";

export default async function SellerLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireRole("seller");

  return <>{children}</>;
}