"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { loginSchema, type LoginInput } from "./login-schema";

export async function login(input: LoginInput) {
  const parsed = loginSchema.safeParse(input);
  if (!parsed.success) {
    return { error: parsed.error.flatten().fieldErrors };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);

  if (error) {
    // Deliberately generic message -- don't reveal whether the email
    // exists or the password was wrong specifically, that distinction
    // helps an attacker enumerate valid accounts.
    return { error: { form: ["Invalid email or password."] } };
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: { form: ["Something went wrong. Please try again."] } };
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();

  // redirect() throws internally -- nothing after it in this function runs,
  // and it must not be wrapped in try/catch that would swallow it.
  if (profile?.role === "admin") {
    redirect("/admin/dashboard");
  }

  if (profile?.role === "agent") {
    redirect("/agent/dashboard");
  }

  if (profile?.role === "seller") {
    const { data: seller } = await supabase
      .from("sellers")
      .select("status")
      .eq("profile_id", user.id)
      .single();

    if (seller?.status !== "active") {
      redirect("/pending-approval");
    }
    redirect("/seller/dashboard");
  }

  // Should be unreachable (every profile has a valid role) -- fallback
  // just in case, rather than leaving the user stuck with no redirect.
  redirect("/login");
}