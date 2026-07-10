import Link from 'next/link';
import { Card } from '@/components/ui/Card';

export default function ResetPasswordPage() {
  return (
    <main className="app-shell flex min-h-screen items-center justify-center px-4 py-10">
      <Card className="max-w-lg text-center">
        <p className="eyebrow mb-3">Account recovery</p>
        <h1 className="text-3xl font-black">Reset password</h1>
        <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
          This clean rebuild has the recovery screen reserved. Once the fresh Supabase project is connected, password reset emails will route here.
        </p>
        <Link className="primary-button mt-5 inline-flex rounded-xl px-4 py-3 text-sm font-black" href="/login">Back to login</Link>
      </Card>
    </main>
  );
}
