import { motion } from 'framer-motion';
import { ArrowUp, Facebook, Instagram, Mail, Phone, Twitter } from 'lucide-react';
import Logo from './Logo.jsx';

const COLUMNS = [
  {
    title: 'Company',
    links: ['About us', 'How it works', 'Careers', 'Press', 'Blog'],
  },
  {
    title: 'For customers',
    links: ['Browse restaurants', 'Offers', 'Delivery areas', 'Help centre', 'Track an order'],
  },
  {
    title: 'For partners',
    links: ['List your kitchen', 'Become a rider', 'Partner login', 'Business orders'],
  },
];

const SOCIALS = [
  { icon: Instagram, label: 'Instagram' },
  { icon: Twitter, label: 'X' },
  { icon: Facebook, label: 'Facebook' },
];

export default function Footer() {
  return (
    <footer className="bg-ink-950 text-white/70">
      {/* ---------------------------- NEWSLETTER ---------------------------- */}
      <div className="container-x border-b border-white/10 py-14">
        <div className="flex flex-col items-start justify-between gap-8 lg:flex-row lg:items-center">
          <div className="max-w-md">
            <h3 className="font-display text-2xl font-bold text-white sm:text-3xl">
              ₦2,000 off your first order
            </h3>
            <p className="mt-2.5 leading-relaxed">
              Drop your email and we will send the code, plus the week&rsquo;s
              offers before anyone else gets them.
            </p>
          </div>

          <form
            // No backend for this — preventDefault keeps the page from doing a
            // full reload on submit. Wiring it up would mean an email service,
            // a consent record, and an unsubscribe flow, none of which this
            // project is about.
            onSubmit={(event) => event.preventDefault()}
            className="flex w-full max-w-md flex-col gap-3 sm:flex-row"
          >
            <label className="relative flex-1">
              <span className="sr-only">Email address</span>
              <Mail className="pointer-events-none absolute left-4 top-1/2 h-4.5 w-4.5 -translate-y-1/2 text-white/40" />
              <input
                type="email"
                required
                placeholder="you@example.com"
                className="w-full rounded-full border-0 bg-white/10 py-3.5 pl-11 pr-4 text-sm text-white ring-1 ring-white/15 transition placeholder:text-white/40 focus:bg-white/15 focus:ring-2 focus:ring-brand-500"
              />
            </label>

            <button type="submit" className="btn-primary btn-lg shrink-0">
              Send my code
            </button>
          </form>
        </div>
      </div>

      {/* ------------------------------ LINKS ------------------------------ */}
      <div className="container-x grid gap-10 py-14 sm:grid-cols-2 lg:grid-cols-5">
        <div className="lg:col-span-2">
          <Logo dark />

          <p className="mt-5 max-w-xs leading-relaxed">
            Nigerian food, delivered hot. Built in Lagos, running in Lagos,
            Abuja and Port Harcourt.
          </p>

          <div className="mt-6 space-y-2.5 text-sm">
            <a
              href="tel:+2348000000000"
              className="flex items-center gap-2.5 transition hover:text-white"
            >
              <Phone className="h-4 w-4 text-brand-500" />
              0800 JOLLOF RUN
            </a>
            <a
              href="mailto:hello@jollofrun.example"
              className="flex items-center gap-2.5 transition hover:text-white"
            >
              <Mail className="h-4 w-4 text-brand-500" />
              hello@jollofrun.example
            </a>
          </div>

          <div className="mt-7 flex gap-2.5">
            {SOCIALS.map((social) => (
              <motion.a
                key={social.label}
                href="#top"
                aria-label={social.label}
                whileHover={{ y: -3 }}
                className="grid h-10 w-10 place-items-center rounded-full bg-white/10 text-white/80 ring-1 ring-white/10 transition hover:bg-brand-600 hover:text-white"
              >
                <social.icon className="h-4.5 w-4.5" />
              </motion.a>
            ))}
          </div>
        </div>

        {COLUMNS.map((column) => (
          <nav key={column.title}>
            <h4 className="font-display text-sm font-bold uppercase tracking-wider text-white">
              {column.title}
            </h4>
            <ul className="mt-4 space-y-2.5 text-sm">
              {column.links.map((link) => (
                <li key={link}>
                  <a
                    href="#top"
                    className="inline-block transition hover:translate-x-0.5 hover:text-white"
                  >
                    {link}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>

      {/* ---------------------------- BOTTOM BAR ---------------------------- */}
      <div className="border-t border-white/10">
        <div className="container-x flex flex-col items-center justify-between gap-4 py-6 text-xs sm:flex-row">
          <p>
            © {new Date().getFullYear()} Jollof Run. A portfolio project — not a
            real delivery service.
          </p>

          <div className="flex items-center gap-5">
            <a href="#top" className="transition hover:text-white">Privacy</a>
            <a href="#top" className="transition hover:text-white">Terms</a>
            <a href="#top" className="transition hover:text-white">Cookies</a>

            <a
              href="#top"
              className="group flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 transition hover:bg-white/20 hover:text-white"
            >
              Back to top
              <ArrowUp className="h-3.5 w-3.5 transition-transform group-hover:-translate-y-0.5" />
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
