"use client";

import { useState } from "react";
import { signUpSeller } from "@/features/auth/actions";
import { MOROCCAN_CITIES, MOROCCAN_BANKS } from "@/features/auth/constants";

export default function SignupPage() {
  const [errors, setErrors] = useState<Record<string, string[]>>({});
  const [pending, setPending] = useState(false);
  const [success, setSuccess] = useState(false);

  async function handleSubmit(formData: FormData) {
    setPending(true);
    setErrors({});

    const password = String(formData.get("password") ?? "");
    const confirmPassword = String(formData.get("confirmPassword") ?? "");

    if (password !== confirmPassword) {
      setErrors({ confirmPassword: ["Passwords do not match"] });
      setPending(false);
      return;
    }

    const result = await signUpSeller({
      email: String(formData.get("email") ?? ""),
      password,
      fullName: String(formData.get("fullName") ?? ""),
      phone: String(formData.get("phone") ?? ""),
      businessName: String(formData.get("businessName") ?? ""),
      city: String(formData.get("city") ?? ""),
      bank: String(formData.get("bank") ?? "") || undefined,
      rib: String(formData.get("rib") ?? "") || undefined,
    });

    setPending(false);

    if (result?.error) {
      setErrors(result.error as Record<string, string[]>);
      return;
    }

    setSuccess(true);
  }

  if (success) {
    return (
      <main className="min-h-screen flex items-center justify-center bg-surface-muted px-4 py-12">
        <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-8 text-center shadow-sm">
          <h1 className="text-xl font-semibold">Check your email</h1>
          <p className="mt-2 text-sm text-text-muted">
            We sent a confirmation link. Once confirmed, sign in and your
            account will be reviewed for approval.
          </p>
          <a
            href="/login"
            className="mt-4 inline-block text-sm font-medium text-brand-purple"
          >
            Back to sign in
          </a>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen flex items-center justify-center bg-surface-muted px-4 py-12">
      <div className="w-full max-w-lg rounded-2xl border border-slate-200 bg-white p-8 shadow-sm">
        <h1 className="text-2xl font-semibold">Create Seller Account</h1>
        <p className="mt-1 text-sm text-text-muted">
          Set up your ZONECOD account and start selling today.
        </p>

        <form action={handleSubmit} className="mt-6 space-y-6">
          <fieldset className="space-y-4">
            <legend className="text-xs font-semibold uppercase tracking-wide text-text-muted">
              Personal Information
            </legend>
            <div className="grid grid-cols-2 gap-4">
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
                {errors.fullName && (
                  <p className="mt-1 text-xs text-danger">{errors.fullName[0]}</p>
                )}
              </div>
              <div>
                <label htmlFor="businessName" className="block text-sm font-medium">
                  Store Name
                </label>
                <input
                  id="businessName"
                  name="businessName"
                  required
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
                />
                {errors.businessName && (
                  <p className="mt-1 text-xs text-danger">{errors.businessName[0]}</p>
                )}
              </div>
            </div>
          </fieldset>

          <fieldset className="space-y-4">
            <legend className="text-xs font-semibold uppercase tracking-wide text-text-muted">
              Contact Details
            </legend>
            <div>
              <label htmlFor="email" className="block text-sm font-medium">
                Email Address
              </label>
              <input
                id="email"
                name="email"
                type="email"
                required
                placeholder="you@email.com"
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
              />
              {errors.email && (
                <p className="mt-1 text-xs text-danger">{errors.email[0]}</p>
              )}
            </div>

            <div>
              <label htmlFor="phone" className="block text-sm font-medium">
                Phone Number
              </label>
              <input
                id="phone"
                name="phone"
                placeholder="+212 6XXXXXXXX"
                required
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
              />
              {errors.phone && (
                <p className="mt-1 text-xs text-danger">{errors.phone[0]}</p>
              )}
            </div>

            <div>
              <label htmlFor="city" className="block text-sm font-medium">
                City
              </label>
              <select
                id="city"
                name="city"
                required
                defaultValue=""
                className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
              >
                <option value="" disabled>
                  Select your city
                </option>
                {MOROCCAN_CITIES.map((city) => (
                  <option key={city} value={city}>
                    {city}
                  </option>
                ))}
              </select>
              {errors.city && (
                <p className="mt-1 text-xs text-danger">{errors.city[0]}</p>
              )}
            </div>
          </fieldset>

          <fieldset className="space-y-4">
            <legend className="text-xs font-semibold uppercase tracking-wide text-text-muted">
              Bank Information (optional)
            </legend>
            <div>
              <label htmlFor="bank" className="block text-sm font-medium">
                Bank
              </label>
              <select
                id="bank"
                name="bank"
                defaultValue=""
                className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
              >
                <option value="">Select your bank</option>
                {MOROCCAN_BANKS.map((bank) => (
                  <option key={bank} value={bank}>
                    {bank}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label htmlFor="rib" className="block text-sm font-medium">
                RIB (24 digits)
              </label>
              <input
                id="rib"
                name="rib"
                inputMode="numeric"
                maxLength={24}
                placeholder="000000000000000000000000"
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-brand-purple"
              />
              {errors.rib && (
                <p className="mt-1 text-xs text-danger">{errors.rib[0]}</p>
              )}
            </div>
          </fieldset>

          <fieldset className="space-y-4">
            <legend className="text-xs font-semibold uppercase tracking-wide text-text-muted">
              Security
            </legend>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label htmlFor="password" className="block text-sm font-medium">
                  Password
                </label>
                <input
                  id="password"
                  name="password"
                  type="password"
                  required
                  placeholder="Min 8 characters"
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
                />
                {errors.password && (
                  <p className="mt-1 text-xs text-danger">{errors.password[0]}</p>
                )}
              </div>
              <div>
                <label htmlFor="confirmPassword" className="block text-sm font-medium">
                  Confirm Password
                </label>
                <input
                  id="confirmPassword"
                  name="confirmPassword"
                  type="password"
                  required
                  placeholder="Repeat password"
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-purple"
                />
                {errors.confirmPassword && (
                  <p className="mt-1 text-xs text-danger">{errors.confirmPassword[0]}</p>
                )}
              </div>
            </div>
          </fieldset>

          {errors.form && <p className="text-sm text-danger">{errors.form[0]}</p>}

          <button
            type="submit"
            disabled={pending}
            className="gradient-brand w-full rounded-lg px-4 py-2.5 text-sm font-medium text-white disabled:opacity-60"
          >
            {pending ? "Creating account..." : "Create Account"}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-text-muted">
          Already have an account?{" "}
          <a href="/login" className="font-medium text-brand-purple">
            Sign in
          </a>
        </p>
      </div>
    </main>
  );
}