import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type Role = "admin" | "agent" | "seller";

/**
 * Server-side role guard -- call this at the top of every protected
 * layout.tsx (app/admin/layout.tsx, app/agent/layout.tsx,
 * app/seller/layout.tsx). This is defense-in-depth ON TOP OF RLS, not a
 * replacement for it: RLS (0012_rls_policies.sql) is what actually
 * protects the DATA even if this check were somehow skipped. This check
 * exists so a wrong-role user gets redirected to a sensible page instead
 * of landing on a role's dashboard and seeing empty/broken UI because
 * every query silently returned nothing due to RLS.
 */
export async function requireRole(allowedRole: Role) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== allowedRole) {
    redirect("/login");
  }

  if (allowedRole === "seller") {
    const { data: seller } = await supabase
      .from("sellers")
      .select("status")
      .eq("profile_id", user.id)
      .single();

    if (seller?.status !== "active") {
      redirect("/pending-approval");
    }
  }

  return { userId: user.id, role: profile.role as Role };
}