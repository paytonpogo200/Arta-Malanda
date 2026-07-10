import Link from 'next/link';
import { Card } from '@/components/ui/Card';

export default function ResetPasswordPage() {
  return (
    <main className="app-shell flex min-h-screen items-center justify-center px-4 py-10">
      <Card className="max-w-lg text-center">
        <p className="eyebrow mb-3">Account recovery</p>
        <h1 className="text-3xl font-black">Reset password</h1>
        <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
          Username accounts do not use email recovery. Password reset tools will live in the DM account panel once account management is wired in.
        </p>
        <Link className="primary-button mt-5 inline-flex rounded-xl px-4 py-3 text-sm font-black" href="/login">Back to login</Link>
      </Card>
    </main>
  );
}
