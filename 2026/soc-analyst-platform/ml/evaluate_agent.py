from investigate import investigate
from groq import Groq, RateLimitError
import os
from dotenv import load_dotenv
import re
import time

load_dotenv()
groq_client = Groq(api_key=os.getenv("GROQ_API_KEY"))

# Test queries covering different scenarios your agent should handle
TEST_QUERIES = [
    "suspicious SSH login attempts",
    "FTP brute force attack",
    "unusual traffic on host-22",
    "port scanning activity",
    "normal benign traffic",
    "denial of service attack",
    "DoS Hulk traffic pattern",
    "slowloris style attack",
]


def call_groq_with_retry(messages, model="openai/gpt-oss-20b", temperature=0, max_retries=5):
    """Calls Groq, automatically waiting and retrying if we hit the rate limit
    instead of crashing. Free tier has a low tokens-per-minute cap, so this
    is expected to trigger sometimes when running many calls back to back."""
    for attempt in range(max_retries):
        try:
            return groq_client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
            )
        except RateLimitError:
            wait_time = 10 * (attempt + 1)  # 10s, 20s, 30s... increasing backoff
            print(f"  Rate limit hit, waiting {wait_time}s before retry ({attempt + 1}/{max_retries})...")
            time.sleep(wait_time)
    raise Exception("Max retries exceeded for Groq API call")


def extract_cited_ids(brief_text: str) -> set:
    """Pulls every alert ID mentioned in [brackets] from the brief."""
    matches = re.findall(r'\[([^\]]+)\]', brief_text)
    cited_ids = set()
    for match in matches:
        # Handle comma-separated multiple IDs in one bracket
        ids = [i.strip() for i in match.split(',')]
        cited_ids.update(ids)
    return cited_ids


def extract_claims_with_citations(brief_text: str):
    """Pulls out each line in the EVIDENCE section along with its cited ID(s)."""
    claims = []
    lines = brief_text.split('\n')
    for line in lines:
        if '[' in line and ']' in line:
            # Strip the citation bracket to get just the claim text
            claim_text = re.sub(r'\[([^\]]+)\]', '', line).strip('- ').strip()
            ids = extract_cited_ids(line)
            if claim_text and ids:
                claims.append({"claim": claim_text, "cited_ids": ids})
    return claims


def check_claim_supported(claim: str, alert_texts: list) -> bool:
    """Uses the LLM as a judge: does the cited alert text actually support this claim?

    Handles two tricky cases that a naive judge prompt gets wrong:
    - Aggregate claims that summarize a pattern across multiple alerts
      (e.g. "all alerts share property X")
    - Negative claims that assert something is absent
      (e.g. "no MITRE technique is associated with this alert")
    Both can be entirely accurate even though they don't literally quote the source text.
    """
    evidence_text = "\n".join(alert_texts)
    judge_prompt = f"""You are a fact-checker evaluating claims made about a set of alerts.

Claim: "{claim}"

Cited alert text (one or more alerts):
{evidence_text}

The claim may summarize a PATTERN across multiple alerts (e.g. "all alerts share X") or
state an ABSENCE (e.g. "no field Y is present"). These can be valid and supported claims
if the pattern or absence is genuinely true across the provided text - check carefully
before rejecting them.

Does the cited alert text support this claim? Answer YES if the claim is a reasonable,
accurate summary or observation about the provided text, even if worded differently.
Answer NO only if the claim states something that contradicts the text or adds specific
facts not derivable from it.

Answer YES or NO only:"""

    response = call_groq_with_retry(
        messages=[{"role": "user", "content": judge_prompt}],
        temperature=0,
    )
    answer = response.choices[0].message.content.strip().upper()
    return answer.startswith("YES")


def evaluate_query(query: str):
    """Runs one query and checks two things:
    1. Did every cited ID actually exist in the retrieved context? (hallucinated ID check)
    2. Does the cited alert text actually support each claim made? (claim support check)
    """
    brief, context = investigate(query)
    context_by_id = {c["alert_id"]: c["text"] for c in context}

    real_ids = set(context_by_id.keys())
    cited_ids = extract_cited_ids(brief)
    hallucinated_ids = cited_ids - real_ids  # citations to IDs that don't exist at all

    # Deeper check: for each claim, does the cited alert text actually support it?
    claims = extract_claims_with_citations(brief)
    unsupported_claims = []
    for c in claims:
        valid_ids_for_claim = [i for i in c["cited_ids"] if i in context_by_id]
        if not valid_ids_for_claim:
            continue  # already caught as a hallucinated ID above, skip double-counting
        alert_texts = [context_by_id[i] for i in valid_ids_for_claim]
        supported = check_claim_supported(c["claim"], alert_texts)
        if not supported:
            unsupported_claims.append(c["claim"])
        time.sleep(2)  # small pause between judge calls to stay under rate limit

    return {
        "query": query,
        "brief": brief,
        "real_ids_available": real_ids,
        "cited_ids": cited_ids,
        "hallucinated_ids": hallucinated_ids,
        "total_claims_checked": len(claims),
        "unsupported_claims": unsupported_claims,
    }


def run_evaluation():
    results = []
    for query in TEST_QUERIES:
        print(f"Testing: {query}...")
        result = evaluate_query(query)
        results.append(result)
        time.sleep(3)  # pause between queries too, on top of the per-claim pause

    print("\n" + "=" * 70)
    print("EVALUATION SUMMARY (with claim-support checking)")
    print("=" * 70)

    total_hallucinated_ids = 0
    total_unsupported_claims = 0
    total_claims_checked = 0

    for r in results:
        print(f"\nQuery: {r['query']}")
        print(f"  Hallucinated IDs (cited but don't exist): {len(r['hallucinated_ids'])}")
        print(f"  Claims checked for support: {r['total_claims_checked']}")
        print(f"  Unsupported claims found: {len(r['unsupported_claims'])}")
        if r["hallucinated_ids"]:
            print(f"    - Hallucinated IDs: {r['hallucinated_ids']}")
        if r["unsupported_claims"]:
            for uc in r["unsupported_claims"]:
                print(f"    - UNSUPPORTED: {uc}")

        total_hallucinated_ids += len(r["hallucinated_ids"])
        total_unsupported_claims += len(r["unsupported_claims"])
        total_claims_checked += r["total_claims_checked"]

    print("\n" + "=" * 70)
    print("OVERALL TOTALS")
    print("=" * 70)
    print(f"Queries tested: {len(results)}")
    print(f"Total claims checked: {total_claims_checked}")
    print(f"Total hallucinated IDs: {total_hallucinated_ids}")
    print(f"Total unsupported claims: {total_unsupported_claims}")
    if total_claims_checked:
        accuracy = (total_claims_checked - total_unsupported_claims) / total_claims_checked * 100
        print(f"Claim support accuracy: {accuracy:.1f}%")
    print("=" * 70)

    return results


if __name__ == "__main__":
    run_evaluation()