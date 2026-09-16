import { logout } from "@/features/auth/logout-action";

// A plain <form action={serverAction}> needs zero client-side JS to work --
// this stays a Server Component. Drop <LogoutButton /> into any protected
// layout/page (admin, agent, seller) without turning that file into a
// Client Component just to handle a click.
export function LogoutButton() {
  return (
    <form action={logout}>
      <button
        type="submit"
        className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-text-primary hover:bg-surface-muted"
      >
        Log out
      </button>
    </form>
  );
}