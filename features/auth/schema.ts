import { z } from "zod";

export const signupSchema = z.object({
  email: z.string().email("Enter a valid email address"),
  password: z.string().min(8, "Password must be at least 8 characters"),
  fullName: z.string().min(2, "Full name is required"),
  phone: z.string().min(8, "Enter a valid phone number"),
  businessName: z.string().min(2, "Business name is required"),
  city: z.string().min(1, "Select your city"),
  bank: z.string().optional(),
  rib: z
    .string()
    .optional()
    .refine((val) => !val || /^\d{24}$/.test(val), {
      message: "RIB must be exactly 24 digits",
    }),
});

export type SignupInput = z.infer<typeof signupSchema>;