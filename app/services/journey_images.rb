# The imagery a journey shows on its cards.
#
# Lifted out of Journey because it is a table of URLs, not behaviour the record
# has: thirteen of them, which is a sixth of the model by RuboCop's count and
# the single largest reason Journey sits over the class-length limit.
#
# These are hand-copied Google-hosted photo URLs rather than anything this app
# fetched. Replacing them with imagery we request properly is its own piece of
# work -- Places Photos with the attribution it requires, or a Mapbox static
# image of the route itself -- and deliberately not done here; this move
# changes nothing about what renders.
module JourneyImages
  module_function

  def for(name:, id:)
    PLACE_IMAGES[name] || PLACEHOLDER_IMAGES[id % PLACEHOLDER_IMAGES.size]
  end

  def carousel(count = 3)
    PLACEHOLDER_IMAGES.sample(count)
  end

  PLACE_IMAGES = {
    "Meguro River Loop" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWl2njWwiwoNU7VP1wL1k6xUW7WE44yFymMmwBdR02vjpWgtTzESUyZIp3coC1r7jb_vCRu1k0XXCX88oKa1_uCUXyVLxSvvICfY90bgHz34aApjX2mFxqvKx2yb15O5kk1t2Xr7=s500",
    "Nakameguro Backstreets" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWktTtpRocPqCncbWpUzH8N3kJPFThuHR7QDz0T5rJfJIrm-aJZH527tUrcfdKShNROAgdRLlTdqAchqvbpOIUxHpiN0SGtqifao75cEDtZJqJRYWY8PLvw2NqsxkEUkkOzS_uxrRA=s500",
    "Yutenji Green Escape" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWnE2AkzMKrI-5MgtOO2We2UIrEOzV_BwPHgdVYLRbe2zf7yDNGwi5w_2AhK107p6HffuR6_M_sP9NfdCZZvfbMIkHzbnKOsRn5YYXZtJH9jgmcMro4uCJ7X9M5pstxXWnSQRAmo=s500",
    "Riverside Stroll" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWkGNINhIGzMsuuEoV0gUJ6s8ecQAyTMbZaPCPFRN7ZIG_-yKM7reK4OoYQRwmz7IuHCa5NHRwUUAhKidWYLF3oT0X3ENAhqrlhyzji2WnvEwQhbgl75JTskGeaJIg0NPgKpHCxGkw=s2000",
    "Park Escape" => "https://images.unsplash.com/photo-1519331379826-f10be5486c6f?q=80&w=1740&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
    "Morning Refresh" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWmmP1UP1q-VF_q4qDur3KpBV4_ep0ioVA2xRh70f_YaZxjDGkOhs9OFKZjOX0riLHMAyAzMVdBX5DarOZ__43op4_2EVsxuvZv10JGVgdvONA_kKKXvFCigqWmLpFTMd5DsIrfX=s2000"
  }.freeze

  # Placeholder images
  PLACEHOLDER_IMAGES = [
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWmIbzDkbQKteSMpmw0K4p3aIYCqEYUxYeNqvziCIeUJMw1IbA5c_vK6BItlm_JAXaj8VHoOpLJhB79I3QiMMHimQVWAFVoICMWLjWkM75mLbaTE_zJIDQnDgBAFACgHFPRmRsod=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWnEDlKMKnY_AIoNOwOwiNUO-j9TFVXlqD5kh9dowSCY2CDtPDCc7FDTWT9t7kMFZ6deIye0Wc5r7ROfhAQuHsbwFrzAxb8zzRkdNTyI23sD0TNIgqMEEeNxf_0b0UsZ1JsK_yXpsQ=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWnhR37unymt0_QfrldIarhGRaf-fHsM-QGWabV6A_f2geaP0LtiPwCywQYl5CHIKT6xiaR-UOexzAiYfwI5w0bPhRT-vf8hboVWYKEwbVipPtbVCR6QuiG7zRJpUepweHii6tt7dg=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWnJxOsyKTWnG9cchTE4I1s5i3xwLddM10Y8M7Hy82_eX-Pahm4Ck3PzwLb7tBGk9iMn4jgvRj6F8OkFApyxZhvFxuU7_Uu9ZERFZUZhHk9t8u_KzyCDuD8Mn6KUDYdT0yKJK9peMA=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWlSD5SFmc2LQPsdORxTNTKJ2ZBQGQNMR45qU_QxBJijKbvGM09DvtP2jAFQX-CCrZVDMK1X7V8cuvBavU2pv86r1efjOcB9npy_zJXcK7t5YiBygtizQcG5VeDxn-NYU53kBPQ=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWlQ_zf5NQskgWi_WmraAlsyj9QFikhmgzlVUNpS11GaT-gNawBt1F5BBw3J42W-kemgym9MZHkF-R7bOoQgdqSzbusap5_sd6mZFgXAUhzCQqhgKmIw4Uzis_qkjJAbACfglVsC=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWlrT_bbmnthSna1Wn41PYAvVSTk10ZEqd_jlLSvAQpsB98emmhyW4kZMD_mWk9Gdk1zO4HWVOV3JlcbwW_QfTVIkpYuYXhwXaMVS3e_XdNToMD2TNSI3Y1NaBzNZbsXsycXcuY7Ig=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWlOSFbSwUg0K8VDbGkylUKgKmaSxp7NACTqhMl_dmdFNGltBJTNUeT2Mnome-6303b3UVXfRctb402DI8DSGG4pClrwZREiazw1LIU2ZDNnJrNUiAmqy39CAn5eFaHXuTZNhyJy2Q=s2000"
  ]
end
