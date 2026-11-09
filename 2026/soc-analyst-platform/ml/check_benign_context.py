from investigate import retrieve_context

context = retrieve_context("normal benign traffic")
for c in context:
    print(c)
    print()