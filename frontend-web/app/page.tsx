import React from 'react';

export default function HomePage() {
  return (
    <main className="min-h-screen bg-neutral-50 text-neutral-900 font-sans">
      <header className="bg-emerald-700 text-white p-6 shadow-md">
        <div className="max-w-5xl mx-auto flex justify-between items-center">
          <h1 className="text-2xl font-black tracking-tight">🏪 Duka Ledger</h1>
          <span className="text-sm bg-emerald-800 px-3 py-1 rounded-full">Community & Buyer Portal</span>
        </div>
      </header>

      <div className="max-w-5xl mx-auto p-6 space-y-8">
        {/* Search & Location Filter */}
        <section className="bg-white p-6 rounded-2xl shadow-sm border border-neutral-200">
          <h2 className="text-xl font-bold mb-4">Tafuta Duka au Mama Mboga Karibu Nawe</h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <input 
              type="text" 
              placeholder="Jina la bidhaa (mf. Nyanya, Sukuma, Unga)..." 
              className="border border-neutral-300 rounded-xl p-3 focus:outline-none focus:ring-2 focus:ring-emerald-500"
            />
            <select className="border border-neutral-300 rounded-xl p-3 bg-white">
              <option>Chagua Kaunti (Nairobi, Kiambu, Mombasa)...</option>
              <option>Nairobi</option>
              <option>Kiambu</option>
            </select>
            <button className="bg-emerald-600 hover:bg-emerald-700 text-white font-bold py-3 px-6 rounded-xl transition">
              Tafuta Sasa
            </button>
          </div>
        </section>

        {/* Featured Shops Nearby */}
        <section className="space-y-4">
          <h3 className="text-lg font-bold text-neutral-800">Maduka Yaliyofunguliwa Sasa (Open Now)</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="bg-white p-5 rounded-2xl border border-neutral-200 shadow-sm flex justify-between items-start">
              <div>
                <span className="text-xs font-semibold px-2 py-0.5 rounded bg-emerald-100 text-emerald-800">Mama Mboga</span>
                <h4 className="font-bold text-lg mt-1">Mama Brian Fresh Veggies</h4>
                <p className="text-sm text-neutral-500">Kibera, Olympic Stage • 500m mbali</p>
                <p className="text-xs text-neutral-600 mt-2">Nyanya Safi, Sukuma Wiki, Vitunguu, Matunda</p>
              </div>
              <a 
                href="https://wa.me/254712345678" 
                className="bg-emerald-50 text-emerald-700 border border-emerald-300 px-3 py-1.5 rounded-lg text-sm font-semibold hover:bg-emerald-100"
              >
                WhatsApp
              </a>
            </div>

            <div className="bg-white p-5 rounded-2xl border border-neutral-200 shadow-sm flex justify-between items-start">
              <div>
                <span className="text-xs font-semibold px-2 py-0.5 rounded bg-blue-100 text-blue-800">Duka Retail</span>
                <h4 className="font-bold text-lg mt-1">Kamau Mini Supermarket</h4>
                <p className="text-sm text-neutral-500">Kawangware Stage 2 • 800m mbali</p>
                <p className="text-xs text-neutral-600 mt-2">Unga wa Pembe, Mafuta ya Kupikia, Sukari, Sabuni</p>
              </div>
              <a 
                href="https://wa.me/254722000111" 
                className="bg-emerald-50 text-emerald-700 border border-emerald-300 px-3 py-1.5 rounded-lg text-sm font-semibold hover:bg-emerald-100"
              >
                WhatsApp
              </a>
            </div>
          </div>
        </section>

        {/* Community Notice Board */}
        <section className="bg-white p-6 rounded-2xl border border-neutral-200 shadow-sm">
          <h3 className="text-lg font-bold mb-3">Tangazo la Mtaa (Community Notice Board)</h3>
          <div className="p-4 bg-amber-50 border-l-4 border-amber-500 rounded-r-xl">
            <h5 className="font-bold text-amber-900">Ilani ya Maji / Water Outage Notice</h5>
            <p className="text-sm text-amber-800 mt-1">
              Kutakuwa na ukosefu wa maji siku ya Alhamisi katika eneo la Olympic kwa sababu ya matengenezo.
            </p>
          </div>
        </section>
      </div>
    </main>
  );
}
