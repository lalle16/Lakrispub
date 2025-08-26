import streamlit as st
import pandas as pd
import requests
import re
from datetime import datetime
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
import matplotlib.pyplot as plt
from io import BytesIO

st.set_page_config(page_title="AlphaVantage EUR/USD News Sentiment", layout="wide")
st.title("AlphaVantage EUR/USD News Sentiment Analyzer")

st.markdown("""
This app fetches news from AlphaVantage, filters for EUR/USD topics, classifies articles, analyzes sentiment, and allows you to export the results. No installation required for users!
""")

# --- Parameters (fixed) ---
API_KEY = "3JU8AMTCVNKTBIT9"
TICKERS = "FOREX:USD,FOREX:EUR"

# --- Fetch news ---
st.header("1. Fetch News from AlphaVantage")
if st.button("Fetch News"):
    last_year = datetime(datetime.now().year-1, 1, 1).strftime("%Y%m%dT%H%M")
    url = "https://www.alphavantage.co/query"
    params = {
        "function": "NEWS_SENTIMENT",
        "tickers": TICKERS,
        "apikey": API_KEY,
        "limit": 1000,
        "sort": "LATEST",
        "time_from": last_year
    }
    response = requests.get(url, params=params)
    data = response.json()
    if "feed" in data:
        news_df = pd.DataFrame(data["feed"])
        st.success(f"Fetched {len(news_df)} news items.")
        st.session_state["news_df"] = news_df
    else:
        st.error("No news data found or API limit reached.")

# --- Filtering logic ---
EARNINGS = [
    r'\b(earnings|quarterly results|q[1-4]\s*\d{4}|eps|guidance|revenue|profit|net income|dividend|buyback|ipo|spinoff)\b',
    r'\b(downgrades?|upgrades?)\b',
]
CRYPTO_EXCLUDE = [
    r'\b(bitcoin|btc|ethereum|eth|altcoin|crypto(?!-?euro)|defi|nft)\b'
]
EURO_STABLECOIN_ALLOW = [
    r'\b(euro[-\s]?stablecoin|euro[-\s]?coin|euroc|eurc|eurt|stasis|euro tether|eur[-\s]?stablecoin)\b'
]
INCLUDE_PATTERNS = [
    r'\b(eur\s*/\s*usd|usd\s*/\s*eur)\b',
    r'\b(us\s*dollar|u\.s\.\s*dollar|usd|greenback|king\s*dollar)\b',
    r'\b(euro(zone| area)?|eur|single\s*currency)\b',
    r'\b(dxy|u\.s\.\s*dollar\s*index|dollar\s*index|bloomberg\s*dollar\s*spot\s*index)\b',
    r'\b(fxe|uup)\b',
    r'\b(ecb|european central bank|lagarde|panetta|cipollone|schaaf)\b',
    r'\b(fed|federal reserve|fomc|powell)\b',
    r'\b(cpi|hicp|pce|nfp|non[-\s]?farm|payrolls|unemployment|pmi|gdp|ifo|zew|recession|stagflation|inflation|deflation|disinflation)\b',
    r'\b(rate(s)?|hike|cut|pivot|pause|qe|qt|balance sheet|dot plot)\b',
    r'\b(tariff(s)?|dut(y|ies)|sanction(s)?|trade\s*war|export controls?|anti[-\s]?dumping|wto dispute)\b',
    r'\b(geopolitic(s|al)|war|conflict|invasion|missile|strike|escalation|coup|border\s*clash|attack|terror)\b',
    r'\b(euro[-\s]?stablecoin|euroc|eurc|eurt|stasis|euro tether|eur[-\s]?stablecoin|digital\s*euro|mica|bafin|allunity)\b',
]
def compile_patterns(patterns):
    return [re.compile(p, re.IGNORECASE) for p in patterns]
EXC_EARN  = compile_patterns(EARNINGS)
EXC_CRYP  = compile_patterns(CRYPTO_EXCLUDE)
ALLOW_EUR = compile_patterns(EURO_STABLECOIN_ALLOW)
INCLUDE   = compile_patterns(INCLUDE_PATTERNS)
def any_match(patterns, text):
    return any(p.search(text) for p in patterns)
def should_exclude(text):
    if any_match(EXC_EARN, text):
        return True
    if any_match(EXC_CRYP, text) and not any_match(ALLOW_EUR, text):
        return True
    return False
def is_relevant(text):
    return any_match(INCLUDE, text)
def filter_eurusd_news(df, text_cols=("title","summary")):
    def combine(row):
        return " ".join(str(row[c]) for c in text_cols if c in row and pd.notnull(row[c]))
    txt = df.apply(combine, axis=1).str.lower()
    keep = txt.apply(lambda t: (not should_exclude(t)) and is_relevant(t))
    return df[keep]

# --- Classify currency ---
usd_patterns = [
    r"\busd\b", r"\bus\.?dollars?\b", r"\bdollars?\b", r"\bgreenbacks?\b", r"\bking\s*dollars?\b"
]
eur_patterns = [
    r"\beur\b", r"\beuros?\b", r"\bsingle\s*currenc(y|ies)\b", r"\beurozone\b", r"\beuro\s*area\b"
]
def classify_currency_regex(title):
    if not isinstance(title, str):
        return "Other"
    title_lower = title.lower()
    usd = any(re.search(p, title_lower) for p in usd_patterns)
    eur = any(re.search(p, title_lower) for p in eur_patterns)
    if usd and eur:
        return "Both"
    elif usd:
        return "USD"
    elif eur:
        return "EUR"
    else:
        return "Other"

# --- Sentiment analysis ---
analyzer = SentimentIntensityAnalyzer()
def get_sentiment_scores(text):
    if not isinstance(text, str):
        return None
    return analyzer.polarity_scores(text)
def sentiment_label(compound):
    if compound is None:
        return "neutral"
    if compound >= 0.05:
        return "positive"
    elif compound <= -0.05:
        return "negative"
    else:
        return "neutral"

# --- Main workflow ---
if "news_df" in st.session_state:
    news_df = st.session_state["news_df"].copy()
    st.header("2. Filter, Classify, and Analyze")
    # Filter
    news_df = filter_eurusd_news(news_df, text_cols=("title", "summary"))
    st.write(f"Filtered to {len(news_df)} relevant news items.")
    # Classify
    news_df["currency_topic"] = news_df["title"].apply(classify_currency_regex)
    # Sentiment
    sentiment_scores = news_df["summary"].apply(get_sentiment_scores)
    sentiment_df = sentiment_scores.apply(pd.Series)
    news_df = pd.concat([news_df, sentiment_df], axis=1)
    news_df["sentiment_text"] = news_df["compound"].apply(sentiment_label)
    # Show table
    st.dataframe(news_df[["title", "summary", "currency_topic", "compound", "sentiment_text"]].head(20))
    # Plot
    if "time_published" in news_df.columns:
        news_df["time_published_dt"] = pd.to_datetime(news_df["time_published"], errors="coerce")
        news_df_sorted = news_df.sort_values("time_published_dt")
        fig, ax = plt.subplots(figsize=(12, 6))
        for topic in ["USD", "EUR"]:
            subset = news_df_sorted[news_df_sorted["currency_topic"] == topic]
            ax.plot(subset["time_published_dt"], subset["compound"], marker="o", linestyle="-", alpha=0.7, label=topic)
        ax.set_title("Sentiment (Compound) Over Time by Currency Topic (USD & EUR)")
        ax.set_xlabel("Time Published")
        ax.set_ylabel("Compound Sentiment")
        ax.set_ylim(-1, 1)
        ax.legend(title="Currency Topic")
        ax.grid(True)
        fig.tight_layout()
        st.pyplot(fig)
    # Export
    st.header("3. Export Results")
    towrite = BytesIO()
    news_df.to_excel(towrite, index=False)
    towrite.seek(0)
    st.download_button(
        label="Download Excel file",
        data=towrite,
        file_name="av_news_df.xlsx",
        mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
else:
    st.info("Click 'Fetch News' to start.")
