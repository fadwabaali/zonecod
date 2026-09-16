"use server";

import { createClient } from "@/lib/supabase/server";
import { signupSchema, type SignupInput } from "./schema";

export async function signUpSeller(input: SignupInput) {
  const parsed = signupSchema.safeParse(input);
  if (!parsed.success) {
    return { error: parsed.error.flatten().fieldErrors };
  }

  const { email, password, fullName, phone, businessName, city, bank, rib } =
    parsed.data;
  const supabase = await createClient();

  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      // IMPORTANT: this `data` object becomes user_metadata, which is
      // client-editable. Never put `role` here. The database trigger
      // (0011_auth_trigger.sql / updated in 0013) ignores this field for
      // role entirely and always defaults a public signup to 'seller' --
      // that default is enforced in the database, not here, on purpose.
      data: {
        full_name: fullName,
        phone,
        business_name: businessName,
        city,
        bank: bank || null,
        rib: rib || null,
      },
    },
  });

  if (error) {
    return { error: { form: [error.message] } };
  }

  return { success: true, userId: data.user?.id };
}