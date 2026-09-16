"use client";

import { useState } from "react";
import { createAgentAccount } from "@/features/agents/actions";

export default function NewAgentPage() {
  const [errors, setErrors] = useState<Record<string, string[]> | string>({});
  const [pending, setPending] = useState(false);
  const [success, setSuccess] = useState(false);

  async function handleSubmit(formData: FormData) {
    setPending(true);
    setErrors({});
    setSuccess(false);

    const result = await createAgentAccount({
      email: String(formData.get("email") ?? ""),
      password: String(formData.get("password") ?? ""),
      fullName: String(formData.get("fullName") ?? ""),
      phone: String(formData.get("phone") ?? "") || undefined,
      agentType: formData.get("agentType") as "call_center" | "packaging",
    });

    setPending(false);

    if (result?.error) {
      setErrors(result.error);
      return;
    }

    setSuccess(true);
  }

  return (
    <div className="mx-auto max-w-lg px-6 py-10">
      <h1 className="text-2xl font-semibold">Create Agent Account</h1>
      <p className="mt-1 text-sm text-text-muted">
        Agents cannot sign up themselves — admin creates every agent account
        directly.
      </p>

      <form action={handleSubmit} className="mt-6 space-y-4">
        <div>
          <label htmlFor="fullName" className="block text-sm font-medium">
            Full Name
          </label>
          <input
            id="fullName"
            name="fullName"
            required
            className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
          />
        </div>

        <div>
          <label htmlFor="email" className="block text-sm font-medium">
            Email Address
          </label>
          <input
            id="email"
            name="email"
            type="email"
            required
            className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
          />
        </div>

        <div>
          <label htmlFor="phone" className="block text-sm font-medium">
            Phone Number (optional)
          </label>
          <input
            id="phone"
            name="phone"
            className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
          />
        </div>

        <div>
          <label htmlFor="agentType" className="block text-sm font-medium">
            Agent Type
          </label>
          <select
            id="agentType"
            name="agentType"
            required
            defaultValue=""
            className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
          >
            <option value="" disabled>
              Select type
            </option>
            <option value="call_center">Call Center</option>
            <option value="packaging">Packaging / Fulfillment</option>
          </select>
        </div>

        <div>
          <label htmlFor="password" className="block text-sm font-medium">
            Temporary Password
          </label>
          <input
            id="password"
            name="password"
            type="password"
            required
            placeholder="Min 8 characters"
            className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
          />
          <p className="mt-1 text-xs text-text-muted">
            Share this with the agent directly — there is no "forgot
            password" flow for agent accounts yet.
          </p>
        </div>

        {typeof errors === "string" && (
          <p className="text-sm text-danger">{errors}</p>
        )}
        {typeof errors === "object" &&
          Object.entries(errors).map(([field, msgs]) => (
            <p key={field} className="text-sm text-danger">
              {msgs[0]}
            </p>
          ))}

        {success && (
          <p className="text-sm text-success">
            Agent account created successfully.
          </p>
        )}

        <button
          type="submit"
          disabled={pending}
          className="gradient-brand w-full rounded-lg px-4 py-2.5 text-sm font-medium text-white disabled:opacity-60"
        >
          {pending ? "Creating..." : "Create Agent Account"}
        </button>
      </form>
    </div>
  );
}