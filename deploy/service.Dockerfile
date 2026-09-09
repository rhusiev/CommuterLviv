# The live service, and the collector: one image, two commands. They share a
# `data/` directory and every line of the package, so building them twice would
# only be a way for the two to drift apart.
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt requirements-live.txt ./
RUN pip install --no-cache-dir -r requirements-live.txt

COPY commuterlviv ./commuterlviv

# `data/` holds the static GTFS feed, the geometry derived from it, and the
# collector's recording. It is a volume in every deployment; the directory is
# made here so the image also runs without one.
RUN useradd --uid 10001 --no-create-home commuterlviv \
    && mkdir data && chown commuterlviv data
USER commuterlviv

EXPOSE 8099
CMD ["python", "-m", "commuterlviv", "serve", "--host", "0.0.0.0", "--port", "8099"]
