"use client";

import { useState } from "react";
import { login } from "@/features/auth/login-action";

export default function LoginPage() {
  const [errors, setErrors] = useState<Record<string, string[]>>({});
  const [pending, setPending] = useState(false);

  async function handleSubmit(formData: FormData) {
    setPending(true);
    setErrors({});

    const result = await login({
      email: String(formData.get("email") ?? ""),
      password: String(formData.get("password") ?? ""),
    });

    // A successful login redirects server-side and never returns here --
    // if we get a result back, it's always an error.
    if (result?.error) {
      setErrors(result.error as Record<string, string[]>);
      setPending(false);
    }
  }

  return (
    <main className="min-h-screen flex items-center justify-center bg-surface-muted px-4 py-12">
      <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-8 shadow-sm">
        <h1 className="text-2xl font-semibold">Welcome back</h1>
        <p className="mt-1 text-sm text-text-muted">
          Sign in to continue managing your business.
        </p>

        <form action={handleSubmit} className="mt-6 space-y-4">
          <div>
            <label htmlFor="email" className="block text-sm font-medium">
              Email address
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              placeholder="you@example.com"
              className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
            />
          </div>

          <div>
            <label htmlFor="password" className="block text-sm font-medium">
              Password
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
            />
          </div>

          {errors.form && (
            <p className="text-sm text-danger">{errors.form[0]}</p>
          )}

          <button
            type="submit"
            disabled={pending}
            className="gradient-brand w-full rounded-lg px-4 py-2.5 text-sm font-medium text-white disabled:opacity-60"
          >
            {pending ? "Signing in..." : "Sign in"}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-text-muted">
          New seller?{" "}
          <a href="/signup" className="font-medium text-brand-purple">
            Create an account
          </a>
        </p>
      </div>
    </main>
  );
}