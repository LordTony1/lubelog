#!/usr/bin/env bash
# Helper script for talking to the LubeLogger REST API directly, instead of
# clicking through the browser UI. Works because this instance has
# EnableAuth=false, so every request is auto-authenticated as root - no
# API key needed. If EnableAuth is ever turned on, add:
#   -H "x-api-key: <key>"
# to every curl call below (generate a key in LubeLogger under
# Profile -> Manage API Keys, role "manager").
#
# Usage:
#   ./lubelogger-api.sh list-vehicles
#   ./lubelogger-api.sh add-vehicle <year> <make> <model> <plate> <fueltype:Gasoline|Diesel|Electric>
#   ./lubelogger-api.sh upload <file-path>                      # prints Location + Name as JSON
#   ./lubelogger-api.sh add-service <vehicleId> <date MM/DD/YYYY> <odometer> <cost> <description> <notes> [file-path]
#
# All arguments with spaces must be quoted.

set -euo pipefail

BASE_URL="${LUBELOGGER_URL:-http://100.92.235.38:8080}"

cmd="${1:-}"
shift || true

case "$cmd" in
  list-vehicles)
    curl -s "$BASE_URL/api/vehicles"
    echo
    ;;

  add-vehicle)
    year="$1"; make="$2"; model="$3"; plate="$4"; fuel="$5"
    curl -s -X POST "$BASE_URL/api/vehicles/add" \
      -H "Content-Type: application/json" \
      -d "{\"Year\":\"$year\",\"Make\":\"$make\",\"Model\":\"$model\",\"Identifier\":\"LicensePlate\",\"LicensePlate\":\"$plate\",\"FuelType\":\"$fuel\"}"
    echo
    ;;

  upload)
    file="$1"
    curl -s -X POST "$BASE_URL/api/documents/upload" \
      -F "documents=@${file}"
    echo
    ;;

  add-service)
    vehicleId="$1"; date="$2"; odometer="$3"; cost="$4"; description="$5"; notes="$6"; file="${7:-}"

    files_json="[]"
    if [[ -n "$file" ]]; then
      upload_result=$(curl -s -X POST "$BASE_URL/api/documents/upload" -F "documents=@${file}")
      # upload_result is a JSON array like [{"location":"/documents/xxx.jpg","name":"xxx.jpg"}]
      location=$(echo "$upload_result" | grep -o '"location":"[^"]*"' | head -1 | cut -d'"' -f4)
      name=$(echo "$upload_result" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
      files_json="[{\"Location\":\"$location\",\"Name\":\"$name\"}]"
    fi

    payload=$(cat <<JSON
{
  "Date": "$date",
  "Odometer": "$odometer",
  "Cost": "$cost",
  "Description": "$description",
  "Notes": "$notes",
  "Files": $files_json
}
JSON
)
    curl -s -X POST "$BASE_URL/api/vehicle/servicerecords/add?vehicleId=$vehicleId" \
      -H "Content-Type: application/json" \
      -d "$payload"
    echo
    ;;

  *)
    echo "Usage: $0 {list-vehicles|add-vehicle|upload|add-service} ..." >&2
    exit 1
    ;;
esac
