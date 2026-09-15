import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function PendingApprovalPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", user.id)
    .single();

  return (
    <main className="min-h-screen flex items-center justify-center bg-surface-muted px-4 py-12">
      <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-8 text-center shadow-sm">
        <h1 className="text-xl font-semibold">Account pending approval</h1>
        <p className="mt-3 text-sm text-text-muted">
          Hi {profile?.full_name ?? "there"}, your seller account is awaiting
          admin approval. You&apos;ll get full access to the marketplace as
          soon as it&apos;s approved.
        </p>

        <form
          action={async () => {
            "use server";
            const supabase = await createClient();
            await supabase.auth.signOut();
            redirect("/login");
          }}
          className="mt-6"
        >
          <button
            type="submit"
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium"
          >
            Log out
          </button>
        </form>
      </div>
    </main>
  );
}