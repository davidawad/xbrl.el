# Inline XBRL fixtures

`aapl-2025-10k-inline.html` is a reduced, verbatim excerpt from Apple Inc.'s
2025 Form 10-K, accession `0000320193-25-000079`, filed October 31, 2025.
It includes the filing's context, USD unit, and FY2025 revenue fact. The full
primary document is at:

https://www.sec.gov/Archives/edgar/data/320193/000032019325000079/aapl-20250927.htm

The corresponding SEC companyconcept endpoint used by the test oracle is:

https://data.sec.gov/api/xbrl/companyconcept/CIK0000320193/us-gaap/RevenueFromContractWithCustomerExcludingAssessedTax.json

# SEC JSON fixtures (Snap Inc, Form 10-K, us-gaap)

Fetched 2026-10-03 from data.sec.gov / www.sec.gov. Snap Inc (CIK 1564408,
ticker SNAP) files Form 10-K with us-gaap facts. Values are untouched; files
are only trimmed (reformatted JSON, rows or fields dropped, nothing edited).

- `snap-us-gaap-revenue.json`: complete response from
  https://data.sec.gov/api/xbrl/companyconcept/CIK0001564408/us-gaap/RevenueFromContractWithCustomerExcludingAssessedTax.json
- `snap-us-gaap-netincomeloss.json`: complete response from
  https://data.sec.gov/api/xbrl/companyconcept/CIK0001564408/us-gaap/NetIncomeLoss.json
- `snap-companyfacts-names.json`: https://data.sec.gov/api/xbrl/companyfacts/CIK0001564408.json
  reduced to the `us-gaap` concept names (each keeps its `label`; `description`
  and `units` dropped, `units` is `{}`) for concept discovery.
- `frame-us-gaap-revenue-usd-cy2024.json`:
  https://data.sec.gov/api/xbrl/frames/us-gaap/RevenueFromContractWithCustomerExcludingAssessedTax/USD/CY2024.json
  with `data` reduced to 5 of the 2970 rows (CIKs 1564408 Snap, 1326801 Meta,
  1506293 Pinterest, 1713445 Reddit, 1652044 Alphabet).
- `company-tickers-snap.json`: the SNAP entry of
  https://www.sec.gov/files/company_tickers.json

# 20-F regression fixture (TSMC, test-only)

Used only by the `xbrl-annual` 20-F/ifrs-full regression tests, not by the docs.
Fetched 2026-10-03; rows are verbatim, trimmed to the USD unit.

- `tsm-ifrs-revenue-20f.json`: from
  https://data.sec.gov/api/xbrl/companyconcept/CIK0001046179/ifrs-full/Revenue.json
  (`TWD` unit dropped)
- `company-tickers-tsm.json`: the TSM entry of
  https://www.sec.gov/files/company_tickers.json
