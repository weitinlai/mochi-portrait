#! /bin/bash

# Enable job control and set process group
set -eo pipefail
set -x

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install bc using the appropriate package manager
install_bc() {
    if command_exists apt-get; then
        sudo apt-get update && sudo apt-get install -y bc
    elif command_exists yum; then
        sudo yum install -y bc
    else
        echo "Error: Could not find package manager to install bc"
        exit 1
    fi
}

# Check and install bc if necessary
if ! command_exists bc; then
    echo "bc is not installed. Installing bc..."
    install_bc
fi

# Function to display help
usage() {
  echo "Usage: $0 -v|--videos_dir videos_dir -o|--output_dir output_dir -w|--weights_dir weights_dir -n|--num_frames num_frames [-r|--resolution resolution]"
  echo "  -v, --videos_dir            Path to the videos directory"
  echo "  -o, --output_dir            Path to the output directory"
  echo "  -w, --weights_dir           Path to the weights directory"
  echo "  -n, --num_frames            Number of frames"
  echo "  -r, --resolution            Video resolution (e.g., 512x768, default: 512x768)"
  exit 1
}

# Function to check if the next argument is missing
check_argument() {
  if [[ -z "$2" || "$2" == -* ]]; then
    echo "Error: Argument for $1 is missing"
    usage
  fi
}

# Parse command-line arguments
RESOLUTION="512x768"  # Default portrait resolution
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -v|--videos_dir) check_argument "$1" "$2"; VIDEOS_DIR="$2"; shift ;;
    -o|--output_dir) check_argument "$1" "$2"; OUTPUT_DIR="$2"; shift ;;
    -w|--weights_dir) check_argument "$1" "$2"; WEIGHTS_DIR="$2"; shift ;;
    -n|--num_frames) check_argument "$1" "$2"; NUM_FRAMES="$2"; shift ;;
    -r|--resolution) check_argument "$1" "$2"; RESOLUTION="$2"; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown parameter passed: $1"; usage ;;
  esac
  shift
done

# Check if all required arguments are provided
if [[ -z "$VIDEOS_DIR" || -z "$OUTPUT_DIR" || -z "$WEIGHTS_DIR" || -z "$NUM_FRAMES" ]]; then
  echo "Error: All arguments are required."
  usage
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "Using script directory: ${SCRIPT_DIR}"

##### Step 1: Trim and resize videos
echo -e "\n\e[1;35m🎬 **Step 1: Trim and resize videos** \e[0m"
# Calculate duration to trim videos
DURATION=$(printf "%.1f" "$(echo "($NUM_FRAMES / 30) + 0.09" | bc -l)")
echo "Trimming videos to duration: ${DURATION} seconds"
python3 ${SCRIPT_DIR}/trim_and_crop_videos.py ${VIDEOS_DIR} ${OUTPUT_DIR} -d ${DURATION} -r ${RESOLUTION}

##### Step 2: Run the VAE encoder on each video.
echo -e "\n\e[1;35m🎥 **Step 2: Run the VAE encoder on each video** \e[0m"

# Parse RESOLUTION into HEIGHT and WIDTH for --shape
HEIGHT=$(echo $RESOLUTION | cut -d'x' -f2)
WIDTH=$(echo $RESOLUTION | cut -d'x' -f1)

python3 ${SCRIPT_DIR}/encode_videos.py ${OUTPUT_DIR} \
  --model_dir ${WEIGHTS_DIR} --num_gpus 1 --shape "${NUM_FRAMES}x${HEIGHT}x${WIDTH}" --overwrite

##### Step 3: Compute T5 embeddings
echo -e "\n\e[1;35m🧠 **Step 3: Compute T5 embeddings** \e[0m"
python3 ${SCRIPT_DIR}/embed_captions.py --overwrite ${OUTPUT_DIR}

echo -e "\n\e[1;32m✓ Done!\e[0m"
