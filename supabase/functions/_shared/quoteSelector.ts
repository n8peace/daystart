// Quote selection utility for deterministic daily quote selection
import { quoteLibrary, getDeterministicQuote, type QuoteCategory } from './quoteLibrary.ts';

// Map iOS enum display values to library keys
export const CATEGORY_MAPPING: Record<string, QuoteCategory> = {
  'Buddhist': 'buddhist',
  'Christian': 'christian',
  'Good Feelings': 'goodFeelings',
  'Hindu': 'hindu',
  'Inspirational': 'inspirational',
  'Jewish': 'jewish',
  'Mindfulness': 'mindfulness',
  'Muslim': 'muslim',
  'Philosophical': 'philosophical',
  'Stoic': 'stoic',
  'Success': 'success',
  'Zen': 'zen'
};

// Get deterministic daily quote based on date and category with timezone awareness
export function getDailyQuote(category: QuoteCategory, date: Date, userTimezone?: string): string | null {
  // Use user's local date if timezone provided, otherwise use UTC
  let localDate = date;
  if (userTimezone) {
    try {
      // Get user's local date at noon to avoid DST edge cases
      const userDateString = date.toLocaleDateString('en-CA', { timeZone: userTimezone }); // YYYY-MM-DD format
      localDate = new Date(`${userDateString}T12:00:00Z`);
    } catch (error) {
      console.warn(`[Quote Selector] Invalid timezone ${userTimezone}, falling back to UTC`);
    }
  }
  
  const selectedQuote = getDeterministicQuote(category, localDate);
  
  if (!selectedQuote) {
    console.warn(`[Quote Selector] No quotes found for category: ${category}`);
    return null;
  }
  
  const dateString = localDate.toISOString().split('T')[0];
  console.log(`[Quote Selector] Selected quote for ${category} on ${dateString}${userTimezone ? ` (${userTimezone})` : ' (UTC)'}: "${selectedQuote.substring(0, 50)}..."`);
  
  return selectedQuote;
}

// Get today's quote for a category (convenience function)
export function getTodaysQuote(category: QuoteCategory, userTimezone?: string): string | null {
  return getDailyQuote(category, new Date(), userTimezone);
}