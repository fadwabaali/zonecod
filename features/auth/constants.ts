// Static lists -- deliberately not database tables, see the comment on
// sellers.city in 0013_seller_banking.sql for why. Update this file
// directly if the list needs to change; no migration required.

export const MOROCCAN_CITIES = [
  "Casablanca",
  "Rabat",
  "Fès",
  "Marrakech",
  "Tanger",
  "Agadir",
  "Meknès",
  "Oujda",
  "Kénitra",
  "Tétouan",
  "Salé",
  "Nador",
  "El Jadida",
  "Béni Mellal",
  "Khouribga",
  "Taza",
  "Settat",
  "Larache",
  "Mohammedia",
  "Safi",
  "Khemisset",
  "Guelmim",
  "Berkane",
  "Taourirt",
  "Ouarzazate",
  "Errachidia",
  "Essaouira",
  "Ifrane",
  "Al Hoceïma",
  "Laâyoune",
  "Dakhla",
] as const;

export const MOROCCAN_BANKS = [
  // Conventional banks
  "Attijariwafa Bank",
  "Banque Populaire (BCP)",
  "Bank of Africa (BMCE)",
  "BMCI",
  "Saham Bank",
  "Crédit du Maroc",
  "CIH Bank",
  "Al Barid Bank",
  "Crédit Agricole du Maroc",
  "CFG Bank",
  "Arab Bank Maroc",
  "Citibank Maghreb",
  // Participative (Islamic) banks
  "Bank Assafa",
  "Umnia Bank",
  "Bank Al Yousr",
  "Al Akhdar Bank",
  "BTI Bank",
] as const;