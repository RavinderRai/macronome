import marimo

__generated_with = "0.17.2"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo
    return


@app.cell
def _():
    import os

    # Get current working directory
    current_dir = os.getcwd()

    # Print it
    print(current_dir)
    return


@app.cell
def _():
    from ml.pantry_scanner.pipeline.pantry_detector import PantryDetector
    return


@app.cell
def _():
    return


if __name__ == "__main__":
    app.run()
